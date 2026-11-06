// Domain/Events/DomainEvent.swift
import Foundation

 enum ChatDomainEvent {
    case newUserStatus(StatusItem)
    case userSeenMyownStatus(StatusItem)

}
