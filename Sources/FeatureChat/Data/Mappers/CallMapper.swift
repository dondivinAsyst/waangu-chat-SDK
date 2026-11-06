//
//  CallMapper.swift
//  FeatureChat
//
//  CallLogModel (GRDB row) ↔ CallLogEntity (domain).
//
//  The two outcome vocabularies are deliberately not the same type: the domain
//  owns `CallOutcome`, storage owns `CallStatusModel`. They happen to have the
//  same cases today, and this is the single place that knows it.
//

import Foundation

enum CallMapper {

    // MARK: - Model → Domain

    static func toDomain(_ model: CallLogModel) -> CallLogEntity {
        CallLogEntity(
            id: model.id,
            userId: model.userId,
            contactId: model.contactId,
            conversationId: model.conversationId,
            contactName: model.contactName,
            contactPhone: model.contactPhone,
            contactAvatarURL: model.contactAvatarURL,
            media: toDomain(model.callType),
            direction: toDomain(model.direction),
            outcome: toDomain(model.status),
            durationSeconds: model.durationSeconds,
            startedAt: model.calledAt,
            endedAt: model.endedAt,
            isGroupCall: model.isGroupCall,
            groupName: model.groupName,
            participantCount: model.participantCount,
            initiatedByUserId: model.initiatedByUserId,
            participants: (model.participants ?? []).map(toDomain)
        )
    }

    static func toDomain(_ participant: CallParticipantModel) -> CallLogParticipant {
        CallLogParticipant(
            userId: participant.userId,
            name: participant.name,
            phone: participant.phone,
            outcome: toDomain(participant.status)
        )
    }

    static func toDomain(_ media: CallMediaTypeModel) -> CallMedia {
        switch media {
        case .voice: return .voice
        case .video: return .video
        }
    }

    static func toDomain(_ direction: CallDirectionModel) -> CallDirection {
        switch direction {
        case .incoming: return .incoming
        case .outgoing: return .outgoing
        }
    }

    static func toDomain(_ status: CallStatusModel) -> CallOutcome {
        switch status {
        case .answered:  return .answered
        case .missed:    return .missed
        case .declined:  return .declined
        case .cancelled: return .cancelled
        case .noAnswer:  return .noAnswer
        case .busy:      return .busy
        case .failed:    return .failed
        }
    }

    // MARK: - Domain → Model

    static func toModel(_ entity: CallLogEntity) -> CallLogModel {
        CallLogModel(
            id: entity.id,
            userId: entity.userId,
            contactId: entity.contactId,
            conversationId: entity.conversationId,
            contactName: entity.contactName,
            contactPhone: entity.contactPhone,
            contactAvatarURL: entity.contactAvatarURL,
            callType: toModel(entity.media),
            direction: toModel(entity.direction),
            status: toModel(entity.outcome),
            durationSeconds: entity.durationSeconds,
            calledAt: entity.startedAt,
            endedAt: entity.endedAt,
            isGroupCall: entity.isGroupCall,
            groupName: entity.groupName,
            participantCount: entity.participantCount,
            initiatedByUserId: entity.initiatedByUserId,
            participants: entity.participants.isEmpty ? nil : entity.participants.map(toModel)
        )
    }

    static func toModel(_ participant: CallLogParticipant) -> CallParticipantModel {
        CallParticipantModel(
            userId: participant.userId,
            name: participant.name,
            phone: participant.phone,
            status: toModel(participant.outcome)
        )
    }

    static func toModel(_ media: CallMedia) -> CallMediaTypeModel {
        switch media {
        case .voice: return .voice
        case .video: return .video
        }
    }

    static func toModel(_ direction: CallDirection) -> CallDirectionModel {
        switch direction {
        case .incoming: return .incoming
        case .outgoing: return .outgoing
        }
    }

    static func toModel(_ outcome: CallOutcome) -> CallStatusModel {
        switch outcome {
        case .answered:  return .answered
        case .missed:    return .missed
        case .declined:  return .declined
        case .cancelled: return .cancelled
        case .noAnswer:  return .noAnswer
        case .busy:      return .busy
        case .failed:    return .failed
        }
    }
}
