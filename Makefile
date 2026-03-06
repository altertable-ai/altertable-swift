.PHONY: lint format test

lint:
	swiftlint

format:
	swiftformat Sources/ Tests/

test:
	swift test
