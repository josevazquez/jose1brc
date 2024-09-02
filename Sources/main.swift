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


struct Result {
    let cities: [Int: City]
    let names: [Int: String]
}


extension [Int: City] {
    mutating func merge(_ other: [Int: City]) {
        let mergedKeys = Set(keys).union(other.keys)
        for key in mergedKeys {
            self[key, default: City()].merge(other[key, default: City()])
        }
    }
}


public typealias Subbuffer = Slice<UnsafeRawBufferPointer>
public extension Subbuffer {
    var string: String {
        return String(decoding: base[startIndex..<endIndex], as: UTF8.self)
    }
    
    mutating func parseUntilSemicolon() throws -> String {
        var end = endIndex
        for index in startIndex..<endIndex {
            if self[index] == 0x3B {  // hex ascii code for ';'
                end = index
                break
            }
        }
        let match = self[startIndex..<end]
        self = dropFirst(match.count + 1)
        return match.string
    }
    
    mutating func parseTemperature() throws -> Int {
        var value = 0
        var negative = false

        for i in startIndex..<endIndex {
            let c = self[i]
            if c == 0x0D || c == 0x0A {
                let count = i - startIndex
                self = dropFirst(count + 1)
                break
            }
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

func parse(_ input: Subbuffer) async throws -> Result {
    var buffer = input
    var cities = [Int: City]()
    var names = [Int: String]()
    
    while !buffer.isEmpty {
        // parserUntilSemicolon
        // city = try buffer.parseUntilSemicolon()
        
        
        var end = buffer.endIndex
        var cityId = 2147483647
        for index in buffer.startIndex..<buffer.endIndex {
            let byte = buffer[index]
            if byte == 0x3B {  // hex ascii code for ';'
                end = index
                break
            } else {
                // hash = hash * 33 XOR charCode (bound into 32bits).
                //hash = (((hash << 5) + hash) ^ string.charCodeAt(i)) & limit;
                
                // 2,147,483,647 is the largest 32bit prime number according to the internet
                //cityId += Int(byte)
                cityId = (((cityId << 5) + cityId) ^ Int(byte)) & 0xffff_ffff_ffff_ff
            }
        }
        if !names.keys.contains(cityId) {
            let match = buffer[buffer.startIndex..<end]
            names[cityId] = match.string
        }
    
        buffer = buffer.dropFirst(end - buffer.startIndex + 1)

        
        let temp = try buffer.parseTemperature()
        cities[cityId, default: City()].add(temp)
    }
    return Result(cities: cities, names: names)
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
            try await withThrowingTaskGroup(of: Result.self) { group in
                for buffer in buffers {
                    group.addTask {
                        try await parse(buffer)
                    }
                }
                
                var cities = [Int: City]()
                var names = [Int: String]()
                for try await partition in group {
                    // need to merge partitions
                    cities.merge(partition.cities)
                    names = partition.names
                }
                return Result(cities: cities, names: names)
            }
        }
    }

    let outputURL = URL(fileURLWithPath: cwdPath).appending(path: "output.txt")
    freopen(outputURL.path().cString(using: .ascii), "w", stdout)
    
    let result = try await task.value
    var idsByName = [String: Int]()
    for (key, name) in result.names {
        idsByName[name] = key
    }
    let sortedCityIDs =  idsByName.keys.sorted().compactMap { idsByName[$0] }
    for cityId in sortedCityIDs {
        let c = result.cities[cityId]!
        let min = String(format: "%.1f", Float(c.minValue)/10)
        let avg = String(format: "%.1f", Float(c.total) / (10 * Float(c.count)))
        let max = String(format: "%.1f", Float(c.maxValue)/10)
        let str = "\(result.names[cityId]!)=\(min)/\(avg)/\(max),"
        print(str)
    }
}

try await main()
