import Testing

@testable import SlopometerCore

@Suite("Typed quota target")
struct GoalTargetTests {
    @Test func keepsOnlyDigits() {
        #expect(Goal.targetDigits("Asad") == "")
        #expect(Goal.targetDigits("1a2") == "12")
        #expect(Goal.targetDigits("-5") == "5")
        #expect(Goal.targetDigits("٣") == "")
        #expect(Goal.targetDigits("12345") == "123")
    }

    @Test func clampsIntoRange() {
        #expect(Goal.target(typed: "") == nil)
        #expect(Goal.target(typed: "Asad") == nil)
        #expect(Goal.target(typed: "0") == 1)
        #expect(Goal.target(typed: "7") == 7)
        #expect(Goal.target(typed: "999") == 999)
        #expect(Goal.target(typed: "4x2") == 42)
    }
}
