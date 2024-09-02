#!/bin/sh
swift build -c release -Xswiftc -strict-concurrency=minimal
cp .build/arm64-apple-macosx/release/jose1brc .

