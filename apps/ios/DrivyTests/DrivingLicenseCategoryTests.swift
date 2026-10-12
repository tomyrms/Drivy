import Foundation
import Testing
import UIKit
@testable import Drivy

struct DrivingLicenseCategoryTests {
    /// Les 16 catégories de l’OAC (art. 3), et elles seules.
    @Test func everyOfficialCategoryIsKnown() {
        let official = ["A", "A1", "B", "B1", "C", "C1", "D", "D1", "BE", "CE", "C1E", "DE", "D1E", "F", "G", "M"]
        #expect(Set(DrivingLicenseCategory.allCases.map(\.code)) == Set(official))
        for code in official {
            #expect(DrivingLicenseCategory(code: code)?.code == code, "\(code)")
        }
    }

    @Test func caseSpacesAndPrefixesDoNotChangeTheCategory() {
        #expect(DrivingLicenseCategory(code: "b") == .b)
        #expect(DrivingLicenseCategory(code: " c1e ") == .c1e)
        #expect(DrivingLicenseCategory(code: "C1 E") == .c1e)
        #expect(DrivingLicenseCategory(code: "Cat. BE") == .be)
        #expect(DrivingLicenseCategory(code: "Permis A1") == .a1)
    }

    /// Une offre d’école, une restriction ou une catégorie étrangère n’emprunte jamais le dessin d’une autre.
    @Test func anUnknownCodeBorrowsNoVehicle() {
        for code in ["", "A35kW", "B96", "TPP", "AM", "Moto", "BX"] {
            #expect(DrivingLicenseCategory(code: code) == nil, "\(code)")
        }
    }

    @Test func everyCategoryHasAnAsset() {
        for category in DrivingLicenseCategory.allCases {
            #expect(UIImage(named: category.assetName) != nil, "\(category.assetName)")
        }
    }
}
