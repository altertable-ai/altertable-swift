//
//  Batcher.swift
//  Altertable
//

import Foundation

/// Buffers analytics payloads and flushes when thresholds, timer, or ``flush(completion:)`` fires.
///
/// All methods must be called from the ``Altertable`` serial queue (`ai.altertable.sdk`).
final class Batcher {
    enum HomogeneousChunk {
        case track([TrackPayload])
        case identify([IdentifyPayload])
        case alias([AliasPayload])
    }

    private var fifo: [Altertable.QueuedRequest]

    private var flushEventThreshold: Int
    private var flushIntervalMs: Int
    private var maxBatchSize: Int

    private var bufferGeneration: Int = 0

    private var flushTimerWorkItem: DispatchWorkItem?
    private var isFlushTimerRunning = false
    /// When `false`, threshold/timer/manual flush do not drain the FIFO (used when tracking consent is not granted).
    private var isSendingEnabled = true
    private let altertableQueue: DispatchQueue

    /// Sends started by the periodic timer — excluded from ``flush(completion:)`` drain.
    private var inFlightTimerCount: Int = 0
    /// Sends from threshold flush, manual flush, or ``updateFlushConfig`` threshold check.
    private var inFlightOtherCount: Int = 0
    private var flushWaiters: [() -> Void] = []

    private let sendChunk: (HomogeneousChunk, @escaping (Result<Void, Error>) -> Void) -> Void

    private let maxDrainIterations = 100

    private static func normalizedMaxBatchSize(_ value: Int) -> Int {
        max(1, value)
    }

    private static func normalizedFlushEventThreshold(_ value: Int) -> Int {
        max(1, value)
    }

    init(
        initialQueue: [Altertable.QueuedRequest],
        flushEventThreshold: Int,
        flushIntervalMs: Int,
        maxBatchSize: Int,
        altertableQueue: DispatchQueue,
        sendChunk: @escaping (HomogeneousChunk, @escaping (Result<Void, Error>) -> Void) -> Void
    ) {
        fifo = initialQueue
        self.flushEventThreshold = Self.normalizedFlushEventThreshold(flushEventThreshold)
        self.flushIntervalMs = flushIntervalMs
        self.maxBatchSize = Self.normalizedMaxBatchSize(maxBatchSize)
        self.altertableQueue = altertableQueue
        self.sendChunk = sendChunk
    }

    var totalCount: Int { fifo.count }

    func snapshotForPersistence() -> [Altertable.QueuedRequest] {
        fifo
    }

    func setSendingEnabled(_ enabled: Bool) {
        isSendingEnabled = enabled
    }

    /// Starts the periodic flush timer. No-op when ``flushIntervalMs`` is `<= 0`.
    func startTimer() {
        scheduleTimerLocked()
    }

    func stopTimer() {
        isFlushTimerRunning = false
        flushTimerWorkItem?.cancel()
        flushTimerWorkItem = nil
    }

    /// Clears buffers and invalidates in-flight generations so late failures do not requeue.
    func clear() {
        fifo.removeAll()
        bufferGeneration += 1
        stopTimer()
    }

    func updateFlushConfig(flushEventThreshold: Int, flushIntervalMs: Int, maxBatchSize: Int) {
        self.flushEventThreshold = Self.normalizedFlushEventThreshold(flushEventThreshold)
        self.flushIntervalMs = flushIntervalMs
        self.maxBatchSize = Self.normalizedMaxBatchSize(maxBatchSize)
        if isSendingEnabled {
            scheduleTimerLocked()
        } else {
            stopTimer()
        }
    }

    /// Whether a periodic flush work item is queued (for unit tests).
    internal var isPeriodicFlushTimerScheduledForTesting: Bool {
        flushTimerWorkItem != nil
    }

    /// - Parameter autoFlush: When `true`, crossing ``flushEventThreshold`` triggers a flush. When `false` (e.g. consent pending), events are only buffered.
    func add(_ request: Altertable.QueuedRequest, autoFlush: Bool) {
        fifo.append(request)
        if autoFlush, isSendingEnabled, fifo.count >= flushEventThreshold {
            dispatchFlush(fromTimer: false)
        }
        completeFlushWaitersIfIdle()
    }

    func dropOldest() {
        guard !fifo.isEmpty else { return }
        fifo.removeFirst()
    }

    func flush(completion: (() -> Void)?) {
        if let completion {
            flushWaiters.append(completion)
        }
        pumpFlushLocked()
        completeFlushWaitersIfIdle()
    }

    private func scheduleTimerLocked() {
        stopTimer()
        guard flushIntervalMs > 0 else { return }

        isFlushTimerRunning = true
        scheduleNextTimerTick()
    }

    private func scheduleNextTimerTick() {
        guard isFlushTimerRunning, flushIntervalMs > 0 else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isFlushTimerRunning else { return }
            self.dispatchFlush(fromTimer: true)
            self.completeFlushWaitersIfIdle()
            self.scheduleNextTimerTick()
        }
        flushTimerWorkItem = workItem
        altertableQueue.asyncAfter(deadline: .now() + .milliseconds(flushIntervalMs), execute: workItem)
    }

    private func dispatchFlush(fromTimer: Bool) {
        guard isSendingEnabled else {
            completeFlushWaitersIfIdle()
            return
        }
        guard !fifo.isEmpty else {
            completeFlushWaitersIfIdle()
            return
        }

        let snapshot = fifo
        fifo.removeAll()

        let generationAtDispatch = bufferGeneration

        var remaining = snapshot
        while !remaining.isEmpty {
            guard let chunk = takeLeadingHomogeneousChunk(from: &remaining) else { break }
            if fromTimer {
                inFlightTimerCount += 1
            } else {
                inFlightOtherCount += 1
            }
            sendChunk(chunk) { [weak self] result in
                guard let self else { return }
                self.altertableQueue.async {
                    self.handleSendCompletion(
                        result: result,
                        chunk: chunk,
                        generationAtDispatch: generationAtDispatch,
                        fromTimer: fromTimer
                    )
                }
            }
        }

        completeFlushWaitersIfIdle()
    }

    private func handleSendCompletion(
        result: Result<Void, Error>,
        chunk: HomogeneousChunk,
        generationAtDispatch: Int,
        fromTimer: Bool
    ) {
        switch result {
        case .success:
            break
        case let .failure(error):
            if generationAtDispatch == bufferGeneration, Requester.isRetryableDeliveryError(error) {
                requeueChunk(chunk)
            }
        }

        if fromTimer {
            inFlightTimerCount -= 1
        } else {
            inFlightOtherCount -= 1
        }
        pumpFlushLocked()
        completeFlushWaitersIfIdle()
    }

    private func requeueChunk(_ chunk: HomogeneousChunk) {
        let items: [Altertable.QueuedRequest]
        switch chunk {
        case let .track(payloads):
            items = payloads.map { .track($0) }
        case let .identify(payloads):
            items = payloads.map { .identify($0) }
        case let .alias(payloads):
            items = payloads.map { .alias($0) }
        }
        for item in items.reversed() {
            fifo.insert(item, at: 0)
        }
    }

    private func pumpFlushLocked() {
        guard isSendingEnabled else { return }
        var iterations = 0
        while iterations < maxDrainIterations, inFlightOtherCount == 0, !fifo.isEmpty {
            dispatchFlush(fromTimer: false)
            iterations += 1
        }
    }

    private func completeFlushWaitersIfIdle() {
        guard inFlightOtherCount == 0, fifo.isEmpty else { return }
        let waiters = flushWaiters
        flushWaiters.removeAll()
        for waiter in waiters {
            waiter()
        }
    }

    private func takeLeadingHomogeneousChunk(from remaining: inout [Altertable.QueuedRequest]) -> HomogeneousChunk? {
        guard !remaining.isEmpty else { return nil }
        switch remaining[0] {
        case .track:
            var payloads: [TrackPayload] = []
            while !remaining.isEmpty, case let .track(payload) = remaining[0], payloads.count < maxBatchSize {
                remaining.removeFirst()
                payloads.append(payload)
            }
            return .track(payloads)
        case .identify:
            var payloads: [IdentifyPayload] = []
            while !remaining.isEmpty, case let .identify(payload) = remaining[0], payloads.count < maxBatchSize {
                remaining.removeFirst()
                payloads.append(payload)
            }
            return .identify(payloads)
        case .alias:
            var payloads: [AliasPayload] = []
            while !remaining.isEmpty, case let .alias(payload) = remaining[0], payloads.count < maxBatchSize {
                remaining.removeFirst()
                payloads.append(payload)
            }
            return .alias(payloads)
        }
    }
}
