//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 3/31/26.

import Foundation
import WaanguCoreKit
import WaanguNetworkKit


public class SharedFeatureRepository: SharedFeatureRepositoryProtocol {

    
    private let dataSource: SharedFeatureDatasourceProtocol
    private let apiErrorMapper: ErrorMapperProtocol
    
    
     public init(
        dataSource: SharedFeatureDatasourceProtocol,
        apiErrorMapper: ErrorMapperProtocol
    ) {
        self.dataSource = dataSource
        self.apiErrorMapper = apiErrorMapper
    }
    
    public func getBalance(forceRefresh: Bool) async -> Result<GetBalance, AppError> {
        do {
            let response = try await dataSource.getBalance(forceRefresh: forceRefresh)

            guard let data = SharedFeatureMappers.map(responseDTO: response) else {
                return .failure(.unknown("No balance data returned"))
            }

            return .success(data)

        } catch let apiError as APIError {
            return .failure(apiErrorMapper.map(apiError))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
    
    public func checkRecipientPhone(phone: String) async -> Result<UserProfile, AppError> {
        let dto = CheckCustomerPhoneRequestDTO(phone: phone)
        do {
            let response = try await dataSource.checkRecipientPhone(dto: dto)

            guard response.err == BusinessStatusCode.success.rawValue else {
                return .failure(.unknown(response.message))
            }
            guard let data = response.data else {
                return .failure(.unknown("No user found for this number"))
            }
            return .success(SharedFeatureMappers.toEntity(dto: data))
        } catch let apiError as APIError {
            return .failure(apiErrorMapper.map(apiError))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }

    public func getUserInfos() async -> Result<UserInfos, AppError> {
        do {
            let response = try await dataSource.getUserInfos()

            guard response.err == BusinessStatusCode.success.rawValue else {
                return .failure(.unknown(response.message))
            }
            guard let data = response.data else {
                return .failure(.unknown("No profile data returned"))
            }
            return .success(SharedFeatureMappers.toEntity(dto: data))
        } catch let apiError as APIError {
            return .failure(apiErrorMapper.map(apiError))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
    
    public func countNewNotifications() async -> Result<CountNewNotification, AppError> {
        do {
            let response = try await dataSource.countNewNotifications()
            if let entity = SharedFeatureMappers.map(responseDTO: response) {
                return .success(entity)
            } else {
                return .failure(.unknown("No data returned"))
            }
            
        } catch let apiError as APIError {
            return .failure(apiErrorMapper.map(apiError))
            
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
}
