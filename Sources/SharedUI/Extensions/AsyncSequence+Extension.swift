//
//  trucn.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


//
//  AsyncSequence+Extensions.swift
//  Pods
//
//  Created by asyst on 12/12/25.
//

import Foundation

public extension AsyncSequence where Element == UInt8 {
    func chunked(by chunkSize: Int) -> AsyncThrowingStream<[UInt8], Error> {
        AsyncThrowingStream { continuation in
            Task {
                var buffer: [UInt8] = []
                buffer.reserveCapacity(chunkSize)

                do {
                    for try await byte in self {
                        buffer.append(byte)

                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }

                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
