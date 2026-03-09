#if canImport(SwiftUI)
    import Altertable
    import SwiftUI

    enum Plan: String, CaseIterable, Identifiable {
        case starter, pro, enterprise
        var id: String {
            rawValue
        }

        var title: String {
            rawValue.capitalized
        }

        var price: Int {
            switch self {
            case .starter: return 9
            case .pro: return 29
            case .enterprise: return 99
            }
        }

        var description: String {
            switch self {
            case .starter: return "Perfect for individuals"
            case .pro: return "Best for small teams"
            case .enterprise: return "For large organizations"
            }
        }
    }

    struct SignupStep: Identifiable {
        let id: Int
        let title: String
        let icon: String

        static let allSteps = [
            SignupStep(id: 1, title: "Personal Info", icon: "person.fill"),
            SignupStep(id: 2, title: "Account Setup", icon: "envelope.fill"),
            SignupStep(id: 3, title: "Choose Plan", icon: "creditcard.fill"),
            SignupStep(id: 4, title: "Welcome!", icon: "sparkles"),
        ]
    }

    // MARK: - Default form values

    private enum FormDefaults {
        static let firstName = "John"
        static let lastName = "Doe"
        static let email = "john.doe@example.com"
        static let password = "password"
    }

    // MARK: - Main funnel view

    struct SignupFunnelView: View {
        @EnvironmentObject private var analytics: Altertable

        @State private var currentStep = 1
        @State private var firstName = FormDefaults.firstName
        @State private var lastName = FormDefaults.lastName
        @State private var email = FormDefaults.email
        @State private var password = FormDefaults.password
        @State private var confirmPassword = FormDefaults.password
        @State private var selectedPlan: Plan = .starter
        @State private var agreeToTerms = false
        @State private var errors: [String: String] = [:]

        var body: some View {
            VStack(spacing: 24) {
                ProgressHeader(currentStep: currentStep, steps: SignupStep.allSteps)
                    .padding(.top)

                ScrollView {
                    VStack(spacing: 24) {
                        renderStep()
                    }
                    .padding()
                }

                if currentStep < 4 {
                    HStack {
                        if currentStep > 1 {
                            Button(action: prevStep) {
                                HStack {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .foregroundColor(.secondary)
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        Button(action: nextStep) {
                            HStack {
                                Text(currentStep == 3 ? "Complete Signup" : "Continue")
                                Image(systemName: "chevron.right")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                } else {
                    Button("Restart", action: handleRestart)
                        .buttonStyle(.borderless)
                        .padding()
                }
            }
        }

        @ViewBuilder
        private func renderStep() -> some View {
            switch currentStep {
            case 1:
                PersonalInfoStep(firstName: $firstName, lastName: $lastName, errors: errors)
                    .screenView(name: "Personal Info", client: analytics)
            case 2:
                AccountSetupStep(email: $email, password: $password, confirmPassword: $confirmPassword, errors: errors)
                    .screenView(name: "Account Setup", client: analytics)
            case 3:
                PlanSelectionStep(selectedPlan: $selectedPlan, agreeToTerms: $agreeToTerms, errors: errors)
                    .environmentObject(analytics)
                    .screenView(name: "Plan Selection", client: analytics)
            case 4:
                WelcomeStep(firstName: firstName, lastName: lastName, email: email, plan: selectedPlan)
                    .environmentObject(analytics)
                    .screenView(name: "Welcome", client: analytics)
            default:
                EmptyView()
            }
        }

        private func validateStep() -> Bool {
            var newErrors: [String: String] = [:]

            switch currentStep {
            case 1:
                validatePersonalInfo(&newErrors)
            case 2:
                validateAccountSetup(&newErrors)
            case 3:
                validatePlanSelection(&newErrors)
            default:
                break
            }

            errors = newErrors
            return newErrors.isEmpty
        }

        private func validatePersonalInfo(_ errors: inout [String: String]) {
            if firstName.isEmpty { errors["firstName"] = "First name is required" }
            if lastName.isEmpty { errors["lastName"] = "Last name is required" }
        }

        private func validateAccountSetup(_ errors: inout [String: String]) {
            if email.isEmpty {
                errors["email"] = "Email is required"
            } else if !email.contains("@") || !email.contains(".") {
                errors["email"] = "Enter a valid email address"
            }
            if password.isEmpty { errors["password"] = "Password is required" }
            if password != confirmPassword { errors["confirmPassword"] = "Passwords do not match" }
        }

        private func validatePlanSelection(_ errors: inout [String: String]) {
            if !agreeToTerms { errors["agreeToTerms"] = "You must agree to the terms" }
        }

        private func nextStep() {
            guard validateStep() else { return }

            switch currentStep {
            case 1:
                analytics.track(event: "Personal Info Completed", properties: ["step": 1])
            case 2:
                analytics.track(event: "Account Setup Completed", properties: ["step": 2])
            case 3:
                analytics.track(event: "Plan Selection Completed", properties: ["step": 3])
                handleSubmit()
                return
            default:
                break
            }

            currentStep += 1
        }

        private func prevStep() {
            currentStep -= 1
        }

        private func handleSubmit() {
            analytics.track(event: "Form Submitted")

            analytics.identify(userId: UUID().uuidString, traits: [
                "email": JSONValue(email),
                "firstName": JSONValue(firstName),
                "lastName": JSONValue(lastName),
                "plan": JSONValue(selectedPlan.rawValue),
            ])

            currentStep = 4
        }

        private func handleRestart() {
            analytics.track(event: "Form Restarted")
            currentStep = 1
            firstName = FormDefaults.firstName
            lastName = FormDefaults.lastName
            email = FormDefaults.email
            password = FormDefaults.password
            confirmPassword = FormDefaults.password
            selectedPlan = .starter
            agreeToTerms = false
            errors = [:]
        }
    }

    // MARK: - Reusable form field

    struct FormField: View {
        let label: String
        let placeholder: String
        @Binding var text: String
        var error: String?
        var isSecure: Bool = false

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.subheadline).bold()
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(error != nil ? Color.red : Color.secondary.opacity(0.3))
                )
                if let error {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
        }
    }

    // MARK: - Progress header

    struct ProgressHeader: View {
        let currentStep: Int
        let steps: [SignupStep]

        var body: some View {
            HStack {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    VStack {
                        ZStack {
                            Circle()
                                .fill(currentStep >= step.id ? Color.blue : Color.secondary.opacity(0.2))
                                .frame(width: 40, height: 40)

                            Image(systemName: step.icon)
                                .foregroundColor(currentStep >= step.id ? .white : .secondary)

                            if currentStep > step.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .offset(x: 15, y: -15)
                                    .background(
                                        Circle()
                                            .fill(Color(NSColor.windowBackgroundColor))
                                            .frame(width: 15, height: 15)
                                            .offset(x: 15, y: -15)
                                    )
                            }
                        }
                    }

                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(currentStep > step.id ? Color.blue : Color.secondary.opacity(0.2))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Step views

    struct PersonalInfoStep: View {
        @Binding var firstName: String
        @Binding var lastName: String
        let errors: [String: String]

        var body: some View {
            VStack(spacing: 20) {
                VStack {
                    Text("Let's get started")
                        .font(.largeTitle).bold()
                    Text("Tell us a bit about yourself")
                        .foregroundColor(.secondary)
                }

                FormField(
                    label: "First Name",
                    placeholder: "Enter your first name",
                    text: $firstName,
                    error: errors["firstName"]
                )
                FormField(
                    label: "Last Name",
                    placeholder: "Enter your last name",
                    text: $lastName,
                    error: errors["lastName"]
                )
            }
        }
    }

    struct AccountSetupStep: View {
        @Binding var email: String
        @Binding var password: String
        @Binding var confirmPassword: String
        let errors: [String: String]

        var body: some View {
            VStack(spacing: 20) {
                VStack {
                    Text("Create your account")
                        .font(.largeTitle).bold()
                    Text("Set up your login credentials")
                        .foregroundColor(.secondary)
                }

                FormField(label: "Email Address", placeholder: "Enter your email", text: $email, error: errors["email"])
                FormField(
                    label: "Password",
                    placeholder: "Create a password",
                    text: $password,
                    error: errors["password"],
                    isSecure: true
                )
                FormField(
                    label: "Confirm Password",
                    placeholder: "Confirm your password",
                    text: $confirmPassword,
                    error: errors["confirmPassword"],
                    isSecure: true
                )
            }
        }
    }

    struct PlanSelectionStep: View {
        @EnvironmentObject private var analytics: Altertable
        @Binding var selectedPlan: Plan
        @Binding var agreeToTerms: Bool
        let errors: [String: String]

        var body: some View {
            VStack(spacing: 20) {
                VStack {
                    Text("Choose your plan")
                        .font(.largeTitle).bold()
                    Text("Select the plan that works best for you")
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 12) {
                    ForEach(Plan.allCases) { plan in
                        Button {
                            selectedPlan = plan
                            analytics.track(event: "Plan Selected", properties: ["plan": JSONValue(plan.rawValue)])
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(plan.title) Plan").bold()
                                    Text(plan.description).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("$\(plan.price)").bold()
                                    Text("/month").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(
                                selectedPlan == plan
                                    ? Color.blue.opacity(0.1)
                                    : Color(NSColor.windowBackgroundColor)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedPlan == plan ? Color.blue : Color.secondary.opacity(0.2))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Toggle(isOn: $agreeToTerms.animation()) {
                    Text("I agree to the Terms of Service and Privacy Policy")
                        .font(.caption)
                }
                .onChange(of: agreeToTerms) { newValue in
                    analytics.track(
                        event: "Terms Agreement Changed",
                        properties: ["agreed": JSONValue(newValue), "step": 3]
                    )
                }

                if let error = errors["agreeToTerms"] {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
        }
    }

    struct WelcomeStep: View {
        @EnvironmentObject private var analytics: Altertable
        let firstName: String
        let lastName: String
        let email: String
        let plan: Plan

        var body: some View {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.green)

                VStack {
                    Text("Welcome aboard!")
                        .font(.largeTitle).bold()
                    Text("Thanks \(firstName), your account has been created successfully.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Account Summary:").bold()
                    Text("Name: \(firstName) \(lastName)")
                    Text("Email: \(email)")
                    Text("Plan: \(plan.title)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    analytics.track(event: "Get Started Clicked")
                } label: {
                    Text("Get Started")
                        .bold()
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
#endif
