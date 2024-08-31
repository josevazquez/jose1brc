#!/usr/bin/env swift
import Foundation

struct City {
    var total: Int
    var count: Int
    var minValue = Int.max
    var maxValue = Int.min

    init() {
        total = 0
        count = 0
    }
    
    mutating func add(_ value: Int) {
        total += value
        count += 1
        minValue = min(value, minValue)
        maxValue = max(value, maxValue)
    }
    
    mutating func merge(_ other: City) {
        total += other.total
        count += other.count
        minValue = min(minValue, other.minValue)
        maxValue = max(maxValue, other.maxValue)
    }
}

extension [String: City] {
    mutating func merge(_ other: [String: City]) {
        let mergedKeys = Set(keys).union(other.keys)
        for key in mergedKeys {
            self[key, default: City()].merge(other[key, default: City()])
        }
    }
}

public typealias Subbuffer = Slice<UnsafeRawBufferPointer>
public extension Subbuffer {
    func prefix(until predicate: (Self.Element) throws -> Bool) rethrows -> Subbuffer {
        let start = startIndex
        var end = endIndex
        for index in startIndex..<endIndex {
            if try predicate(self[index]) == false {
                end = index
                break
            }
        }
        return self[start..<end]
    }
    
    var string: String {
        return String(decoding: base[startIndex..<endIndex], as: UTF8.self)
    }
    
    mutating func parseUntilSemicolon() throws -> String {
        let match = prefix { $0 != 0x3B } // hex ascii code for ;
        self = dropFirst(match.count + 1)
        return match.string
    }
    
    mutating func parseTemperature() throws -> Int {
        // hex ascii code for carriage return or new line
        let match = prefix { $0 != 0x0D && $0 != 0x0A }
        self = dropFirst(match.count + 1)
        var value = 0
        var negative = false
        for i in match.startIndex..<match.endIndex {
            let c = match[i]
            if c == 45 { // ascii for `-`
                negative = true
            } else {
                if c > 47 {
                    value = (value * 10) + (Int(c) - 48)
                }
            }
        }
        value = negative ? -value : value
        return value
    }

}

func partition(buffer: Subbuffer, into count: Int) throws -> [Subbuffer] {
    let partitionSize = (buffer.endIndex - buffer.startIndex) / count
    let estimatedBoundaries = (1...count-1).map { $0 * partitionSize }

    let startBoundaries = try estimatedBoundaries.map { boundary in
        var temp = buffer[boundary..<buffer.endIndex]
        _ = try temp.parseTemperature()
        return temp.startIndex
    }
    
    var buffers = [Subbuffer]()
    var start = buffer.startIndex
    for end in startBoundaries {
        buffers.append(buffer[start..<end])
        start = end
    }
    buffers.append(buffer[start..<buffer.endIndex])
    return buffers
}

func parse(buffer: Subbuffer) async throws -> [String: City] {
    var cities = [String: City]()
    var subbuffer = buffer
    var city: String
    var temp: Int
    
    while !subbuffer.isEmpty {
        city = try subbuffer.parseUntilSemicolon()
        temp = try subbuffer.parseTemperature()
        cities[city, default: City()].add(temp)
    }
    return cities
}

func main() async throws {
    guard CommandLine.arguments.count >= 2 else {
        print("missing file argument")
        return
    }
    
    let file = CommandLine.arguments[1]
    let partitionCount = ProcessInfo().activeProcessorCount

    let cwdPath = FileManager.default.currentDirectoryPath
    var url: URL
    if file.first == "/" {
        url = URL(filePath: file)
    } else {
        url = URL(filePath: cwdPath).appending(path: file).standardizedFileURL
    }
    guard FileManager.default.fileExists(atPath: url.path()) else {
        print("file not found: \(url.path())")
        return
    }
    
    let inputData = try Data(contentsOf: url, options: .mappedIfSafe)
    let task = try inputData.withUnsafeBytes { unsafeRawBufferPointer in
        let subbuffer = unsafeRawBufferPointer[...]
        let buffers = try partition(buffer: subbuffer, into: partitionCount)
        return Task {
            try await withThrowingTaskGroup(of: [String: City].self) { group in
                for buffer in buffers {
                    group.addTask {
                        try await parse(buffer: buffer)
                    }
                }
                
                var cities = [String: City]()
                for try await partition in group {
                    // need to merge partitions
                    cities.merge(partition)
                }
                return cities
            }
        }
    }
    
    let cities = try await task.value
    for city in cities.keys.sorted() {
        let c = cities[city]!
        let min = String(format: "%.1f", Float(c.minValue)/10)
        let avg = String(format: "%.1f", Float(c.total) / (10 * Float(c.count)))
        let max = String(format: "%.1f", Float(c.maxValue)/10)
        print("\(city)=\(min)/\(avg)/\(max),")
    }
}

try await main()
