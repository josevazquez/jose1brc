#!/usr/bin/env swift
import Foundation

struct City {
    var total: Double
    var count: Int
    var min = Double.greatestFiniteMagnitude
    var max = -(Double.greatestFiniteMagnitude)

    init() {
        total = 0
        count = 0
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
    
    mutating func parseUntilNewline() throws -> String {
        // hex ascii code for carriage return or new line
        let match = prefix { $0 != 0x0D && $0 != 0x0A }
        self = dropFirst(match.count + 1)
        return match.string
    }
}

func main() async throws {
    guard CommandLine.arguments.count >= 2 else {
        print("missing file argument")
        return
    }
    
    let file = CommandLine.arguments[1]
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
    
    var cities = [String: City]()
  
    let inputData = try Data(contentsOf: url, options: .mappedIfSafe)
    try inputData.withUnsafeBytes { unsafeRawBufferPointer in
        var city: String
        var temp: String
        var subbuffer = unsafeRawBufferPointer[...]
        
        while !subbuffer.isEmpty {
            city = try subbuffer.parseUntilSemicolon()
            temp = try subbuffer.parseUntilNewline()
            var c = cities[city, default: City()]
            let val = Double(temp)!
            c.total += val
            c.count += 1
            c.min = min(val, c.min)
            c.max = max(val, c.max)
            cities[city] = c
        }
    }
    
    for city in cities.keys.sorted() {
        let c = cities[city]!
        let min = String(format: "%.1f", c.min)
        let avg = String(format: "%.1f", c.total / Double(c.count))
        let max = String(format: "%.1f", c.max)
        print("\(city)=\(min)/\(avg)/\(max),")
    }
}

try await main()
