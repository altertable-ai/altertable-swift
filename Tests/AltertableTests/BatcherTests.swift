//
//  BatcherTests.swift
//  AltertableTests
//

import XCTest
@testable import Altertable

final class BatcherTests: XCTestCase {
    private let testQueue = DispatchQueue(label: "ai.altertable.batcher.tests")

    private func sampleTrackPayload(event: String) -> TrackPayload {
        TrackPayload(
            timestamp: "2020-01-01T00:00:00Z",
            event: event,
            environment: "test",
            deviceId: "device-1",
            distinctId: "anonymous-1",
            anonymousId: nil,
            sessionId: "session-1",
            properties: [:]
        )
    }

    private func sampleIdentifyPayload(distinctId: String) -> IdentifyPayload {
        IdentifyPayload(
            environment: "test",
            deviceId: "device-1",
            distinctId: distinctId,
            anonymousId: "anonymous-1",
            traits: [:]
        )
    }

    // MARK: - Threshold

    func testFlushEventThresholdTriggersSend() {
        let expectation = expectation(description: "threshold flush")
        expectation.expectedFulfillmentCount = 1

        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 2,
            flushIntervalMs: 0,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { _, completion in
                expectation.fulfill()
                completion(.success(()))
            }
        )

        testQueue.sync {
            batcher.add(.track(sampleTrackPayload(event: "a")), autoFlush: true)
            batcher.add(.track(sampleTrackPayload(event: "b")), autoFlush: true)
        }

        waitForExpectations(timeout: 1.0)
    }

    func testBelowThresholdDoesNotSend() {
        let expectation = expectation(description: "no send")
        expectation.isInverted = true

        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 3,
            flushIntervalMs: 0,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { _, completion in
                expectation.fulfill()
                completion(.success(()))
            }
        )

        testQueue.sync {
            batcher.add(.track(sampleTrackPayload(event: "a")), autoFlush: true)
            batcher.add(.track(sampleTrackPayload(event: "b")), autoFlush: true)
        }

        waitForExpectations(timeout: 0.2)
    }

    // MARK: - Manual flush

    func testManualFlushDrainsBuffer() {
        let expectation = expectation(description: "manual flush")

        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 100,
            flushIntervalMs: 0,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { _, completion in
                expectation.fulfill()
                completion(.success(()))
            }
        )

        testQueue.sync {
            batcher.add(.track(sampleTrackPayload(event: "solo")), autoFlush: true)
            batcher.flush(completion: nil)
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Chunking

    func testFlushEventThresholdZeroClampsToOne() {
        let expectation = expectation(description: "threshold 0 clamps to 1 so first event triggers send")
        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 0,
            flushIntervalMs: 0,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { chunk, completion in
                if case let .track(payloads) = chunk {
                    XCTAssertEqual(payloads.count, 1)
                } else {
                    XCTFail("Expected track chunk")
                }
                expectation.fulfill()
                completion(.success(()))
            }
        )

        testQueue.sync {
            batcher.add(.track(sampleTrackPayload(event: "only")), autoFlush: true)
        }

        waitForExpectations(timeout: 1.0)
    }

    func testMaxBatchSizeZeroClampsToOne() {
        let expectation = expectation(description: "single send with one payload")
        var sendCount = 0

        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 1,
            flushIntervalMs: 0,
            maxBatchSize: 0,
            altertableQueue: testQueue,
            sendChunk: { chunk, completion in
                sendCount += 1
                if case let .track(payloads) = chunk {
                    XCTAssertEqual(payloads.count, 1)
                } else {
                    XCTFail("Expected track chunk")
                }
                expectation.fulfill()
                completion(.success(()))
            }
        )

        testQueue.sync {
            batcher.add(.track(sampleTrackPayload(event: "only")), autoFlush: true)
        }

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(sendCount, 1)
    }

    func testMaxBatchSizeSplitsIntoMultipleSends() {
        let expectation = expectation(description: "chunked")
        expectation.expectedFulfillmentCount = 2

        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 100,
            flushIntervalMs: 0,
            maxBatchSize: 2,
            altertableQueue: testQueue,
            sendChunk: { chunk, completion in
                if case let .track(payloads) = chunk {
                    XCTAssertLessThanOrEqual(payloads.count, 2)
                } else {
                    XCTFail("Expected track chunk")
                }
                expectation.fulfill()
                completion(.success(()))
            }
        )

        testQueue.sync {
            batcher.add(.track(sampleTrackPayload(event: "1")), autoFlush: true)
            batcher.add(.track(sampleTrackPayload(event: "2")), autoFlush: true)
            batcher.add(.track(sampleTrackPayload(event: "3")), autoFlush: true)
            batcher.flush(completion: nil)
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Mixed types

    func testMixedEventTypesProduceSeparateChunks() {
        let expectation = expectation(description: "mixed")
        expectation.expectedFulfillmentCount = 2
        var sawTrack = false
        var sawIdentify = false

        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 100,
            flushIntervalMs: 0,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { chunk, completion in
                switch chunk {
                case .track:
                    sawTrack = true
                case .identify:
                    sawIdentify = true
                case .alias:
                    XCTFail("Unexpected alias")
                }
                expectation.fulfill()
                completion(.success(()))
            }
        )

        testQueue.sync {
            batcher.add(.track(sampleTrackPayload(event: "e")), autoFlush: true)
            batcher.add(.identify(sampleIdentifyPayload(distinctId: "u1")), autoFlush: true)
            batcher.flush(completion: nil)
        }

        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(sawTrack)
        XCTAssertTrue(sawIdentify)
    }

    // MARK: - Retryable requeue

    func testRetryableFailureRequeuesChunk() {
        let firstFailure = expectation(description: "first attempt fails")
        let secondSuccess = expectation(description: "second attempt succeeds")
        var sendCount = 0

        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 1,
            flushIntervalMs: 0,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { _, completion in
                sendCount += 1
                if sendCount == 1 {
                    firstFailure.fulfill()
                    completion(.failure(APIError.httpError(500)))
                } else {
                    secondSuccess.fulfill()
                    completion(.success(()))
                }
            }
        )

        testQueue.sync {
            batcher.add(.track(sampleTrackPayload(event: "retry_me")), autoFlush: true)
        }

        wait(for: [firstFailure, secondSuccess], timeout: 2.0, enforceOrder: true)
        XCTAssertEqual(sendCount, 2)
    }

    // MARK: - Clear / generation

    func testClearEmptiesBufferWithoutSending() {
        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 100,
            flushIntervalMs: 0,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { _, _ in
                XCTFail("flush should not run while consent-style buffering skips autoFlush")
            }
        )

        testQueue.sync {
            batcher.add(.track(sampleTrackPayload(event: "x")), autoFlush: false)
            XCTAssertEqual(batcher.totalCount, 1)
            batcher.clear()
            XCTAssertEqual(batcher.totalCount, 0)
        }
    }

    /// Late failure after `clear()` must not put payloads back (generation guard).
    func testClearPreventsStaleRequeue() {
        let sendExpectation = expectation(description: "send scheduled")

        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 1,
            flushIntervalMs: 0,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { [unowned self] _, completion in
                sendExpectation.fulfill()
                self.testQueue.asyncAfter(deadline: .now() + 0.15) {
                    completion(.failure(APIError.httpError(500)))
                }
            }
        )

        testQueue.sync {
            batcher.add(.track(sampleTrackPayload(event: "x")), autoFlush: true)
        }

        wait(for: [sendExpectation], timeout: 1.0)

        testQueue.sync {
            batcher.clear()
        }

        let settled = expectation(description: "late failure processed")
        testQueue.asyncAfter(deadline: .now() + 0.35) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1.0)

        testQueue.sync {
            XCTAssertEqual(batcher.totalCount, 0, "Stale failure after clear must not requeue")
        }
    }

    // MARK: - Timer

    /// `flush()` settles without waiting on sends started by the interval timer.
    func testFlushDoesNotWaitForTimerStartedSends() {
        let sendStarted = expectation(description: "timer-driven send started")
        let flushSettled = expectation(description: "flush completed while timer send in flight")
        var pendingCompletion: ((Result<Void, Error>) -> Void)?

        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 100,
            flushIntervalMs: 50,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { _, completion in
                sendStarted.fulfill()
                pendingCompletion = completion
            }
        )

        testQueue.sync {
            batcher.startTimer()
            batcher.add(.track(sampleTrackPayload(event: "t1")), autoFlush: true)
        }

        wait(for: [sendStarted], timeout: 2.0)

        testQueue.sync {
            batcher.flush(completion: {
                flushSettled.fulfill()
            })
        }

        wait(for: [flushSettled], timeout: 1.0)

        testQueue.sync {
            pendingCompletion?(.success(()))
            batcher.stopTimer()
        }
    }

    func testFlushWaitsForThresholdStartedSend() {
        let sendStarted = expectation(description: "threshold send started")
        let flushSettled = expectation(description: "flush settled after send")
        var resolveSend: ((Result<Void, Error>) -> Void)?

        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 1,
            flushIntervalMs: 0,
            maxBatchSize: 1,
            altertableQueue: testQueue,
            sendChunk: { _, completion in
                if resolveSend == nil {
                    sendStarted.fulfill()
                    resolveSend = completion
                } else {
                    completion(.success(()))
                }
            }
        )

        testQueue.sync {
            batcher.add(.track(sampleTrackPayload(event: "t1")), autoFlush: true)
        }

        wait(for: [sendStarted], timeout: 1.0)

        var flushFinished = false
        testQueue.sync {
            batcher.flush {
                flushFinished = true
                flushSettled.fulfill()
            }
            XCTAssertFalse(flushFinished, "flush must not complete until threshold-started send finishes")
            resolveSend?(.success(()))
        }

        wait(for: [flushSettled], timeout: 1.0)
    }

    func testTimerFlushesWhenIntervalElapses() {
        let expectation = expectation(description: "timer flush")

        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 100,
            flushIntervalMs: 150,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { _, completion in
                expectation.fulfill()
                completion(.success(()))
            }
        )

        testQueue.sync {
            batcher.startTimer()
            batcher.add(.track(sampleTrackPayload(event: "timed")), autoFlush: true)
        }

        waitForExpectations(timeout: 2.0)

        testQueue.sync {
            batcher.stopTimer()
        }
    }

    // MARK: - updateFlushConfig vs sending

    func testUpdateFlushConfigDoesNotScheduleTimerWhenSendingDisabled() {
        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 20,
            flushIntervalMs: 0,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { _, completion in
                XCTFail("sendChunk must not run")
                completion(.success(()))
            }
        )

        testQueue.sync {
            batcher.setSendingEnabled(false)
            batcher.updateFlushConfig(
                flushEventThreshold: 20,
                flushIntervalMs: 150,
                maxBatchSize: 10
            )
            XCTAssertFalse(
                batcher.isPeriodicFlushTimerScheduledForTesting,
                "Periodic flush must not be scheduled when sending is disabled"
            )
        }
    }

    func testUpdateFlushConfigSchedulesTimerWhenSendingEnabled() {
        let batcher = Batcher(
            initialQueue: [],
            flushEventThreshold: 100,
            flushIntervalMs: 0,
            maxBatchSize: 10,
            altertableQueue: testQueue,
            sendChunk: { _, completion in
                completion(.success(()))
            }
        )

        testQueue.sync {
            batcher.setSendingEnabled(true)
            batcher.updateFlushConfig(
                flushEventThreshold: 20,
                flushIntervalMs: 150,
                maxBatchSize: 10
            )
            XCTAssertTrue(batcher.isPeriodicFlushTimerScheduledForTesting)
            batcher.stopTimer()
        }
    }
}
