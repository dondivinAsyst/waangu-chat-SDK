//
//  ChatDomainEventBus.swift
//  Pods
//
//  Created by asyst on 12/8/25.
//

import Combine
import Foundation


protocol ChatDomainEventBusProtocol {
    func publish(_ event: ChatDomainEvent)
    func subscribe(_ listener: @escaping (ChatDomainEvent) -> Void)
}



final class InMemoryEventBus: ChatDomainEventBusProtocol {
    private var listeners = [(ChatDomainEvent) -> Void]()
    private let queue = DispatchQueue(label: "EventBusQueue") // thread-safe

    func publish(_ event: ChatDomainEvent) {
        queue.async {
            self.listeners.forEach { $0(event) }
        }
    }

    func subscribe(_ listener: @escaping (ChatDomainEvent) -> Void) {
        queue.async {
            self.listeners.append(listener)
        }
    }
}
