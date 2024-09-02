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

func main() async throws {
    guard CommandLine.arguments.count >= 2 else {
        print("missing file argument")
        return
    }
    let file = CommandLine.arguments[1]
    let cwdPath = FileManager.default.currentDirectoryPath
    
    let url = URL(filePath: cwdPath).appending(path: file).standardizedFileURL

    guard FileManager.default.fileExists(atPath: url.path()) else {
        print("file not found: \(url.path())")
        return
    }

    let inputData = try Data(contentsOf: url, options: .mappedIfSafe)
    try inputData.withUnsafeBytes { unsafeRawBufferPointer in
        var subbuffer = unsafeRawBufferPointer[...]
    }
    
    var cities = [String: City]()
    for try await line in url.lines {
        let values = line.split(separator: ";")
        // print(">>>>\(vclues[0])i+++++\(values[1])<<<<<<")
        let key = String(values[0])
        var c = cities[key, default: City()]
        let val = Double(values[1])!
        c.total += val
        c.count += 1
        c.min = min(val, c.min)
        c.max = max(val, c.max)
        cities[key] = c
    }
    for key in cities.keys.sorted() {
        let c = cities[key]!
        let min = String(format: "%.1f", c.min)
        let avg = String(format: "%.1f", c.total / Double(c.count))
        let max = String(format: "%.1f", c.max)
        print("\(key)=\(min)/\(avg)/\(max),")
    }
}

try await main()
