//
//  SidebarItemTests.swift
//  berthTests
//

import Testing
@testable import berth

struct SidebarItemTests {

    @Test func titlesAndIcons() {
        #expect(SidebarItem.dashboard.title == "Dashboard")
        #expect(SidebarItem.containers.title == "Containers")
        #expect(SidebarItem.containers.icon == "rectangle.stack")
    }

    @Test func searchPlaceholderNilOnlyForNonListScreens() {
        let noSearch: Set<SidebarItem> = [.dashboard, .builds, .system]
        for item in SidebarItem.allCases {
            if noSearch.contains(item) {
                #expect(item.searchPlaceholder == nil)
            } else {
                #expect(item.searchPlaceholder != nil)
            }
        }
    }

    @Test func sectionsPartitionAllCases() {
        let workspace = SidebarItem.items(in: .workspace)
        let system = SidebarItem.items(in: .system)
        #expect(Set(workspace).isDisjoint(with: Set(system)))
        #expect(Set(workspace + system) == Set(SidebarItem.allCases))
        #expect(Set(system) == [.registries, .system])
    }
}
