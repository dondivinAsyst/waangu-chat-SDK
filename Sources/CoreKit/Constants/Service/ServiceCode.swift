//
//  ServiceCode.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

/// Codes de service backend pour toutes les opérations transactionnelles.
///
/// Chaque `rawValue` correspond exactement au code attendu par l'API.
/// Regroupés par catégorie fonctionnelle pour la lisibilité.
public enum ServiceCode: String, Sendable, CaseIterable {

    // MARK: - Wallet Operations

    case topUp                          = "D3KUYDL4"
    case walletToWallet                 = "TRANSFERTOWALLET"
    case bankToWallet                   = "TransferinFake"
    case walletToBank                   = "Subscriber  - Transferout - fake"
    case topUpViaBancobu                = "TOPUPVIABANCOBU"

    // MARK: - Transfers

    case transferToNRIC                 = "TRANSFERTONRIC"
    case transferToMobile               = "TRANSFERTOMOBILE"
    case transferToBank                 = "UV8234443"

    // MARK: - Cash Out

    case cashOut                        = "SUBSCRIBERCASHOUTATAGENT"
    case cashOutAtATM                   = "65SUNX0X2"
    case cashOutNinjaVan                = "CASHOUTNINJAVAN"

    // MARK: - Payments

    case subscriberPayMerchant          = "SUBSCRIBERPAYMERCHANT"
    case subscriberPayOnlineMerchant    = "SUBSPAYONLINEMERCHANT"

    // MARK: - Bill Payments

    case canalPlusBillPayment           = "4DN188516"
    case steamBillPayment               = "NOW871528"
    case anandaBillPayment              = "XY1879476"
    case cashPowerPayment               = "PAYEMENTCHASHPOWER"
    case customerPayElectricity         = "CUSTOMERPAYELECTRICITY"

    // MARK: - Bundles & Telecom

    case getTelcoBundles                = "GETTELCOBUNDLES"
    case subscriberEconetTopUp          = "SUBCRIBERECONETTOPUP"

    // MARK: - Bank Linking

    case linkBancobu                    = "GO65P1YT3V2"
    case subscriberLinkEcobank          = "SUBSCRIBERLINKECOBANK"

    // MARK: - Bills & Utilities

    case getRegidesoBills               = "GETREGIDESOBILLS"
    case getStartimesPackages           = "GETSTARTIMESPACKAGES"

    // MARK: - Education

    case educationFees                  = "EDUCATIONFEES"
    case unibusSchoolFees               = "UNIBUSCHOOLFEES"

    // MARK: - Tax & Government

    case obrEntryPoints                 = "OBRENTRYPOINTS"
    case subscriberPayTaxOBR            = "SUBSCRIBERPAYTAXOBR"

    // MARK: - Insurance

    case insuranceEntry                 = "INSURANCEINT"
    case subscriberBuySayaSompoInsurance = "SUBSCRIBERTBUYSAYASOMPOINSURANCE"
    case subscriberSayaSompoTravel      = "SUBSCRIBERAYASOMPOTRAVEL"

    // MARK: - Virtual Cards

    case virtualCardsEntryPoint         = "WAANGUVIRTUALCARDSENTRYPOINT"
    case subscriberPayVirtualCard       = "SUBSCRIBERPAYVIRTUALCARD"

    // MARK: - Salary & Referral

    case subscriberReqAdvanceSalary     = "SUBSREQADVANCESALARY"
    case subscriberInviteViaReferCode   = "SUBSCRIBERINVITEVIAREERCODE"

    // MARK: - Notifications

    case thirdPartyFirebaseNotification = "THIRDPARTYFIREBASENOTIFICATION"
}
