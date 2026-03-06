import SwiftUI
import Altertable

enum Plan: String, CaseIterable, Identifiable {
    case starter, pro, enterprise
    var id: String { self.rawValue }
    
    var title: String { self.rawValue.capitalized }
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

struct SignupStep {
    let id: Int
    let title: String
    let icon: String
}

let STEPS = [
    SignupStep(id: 1, title: "Personal Info", icon: "person.fill"),
    SignupStep(id: 2, title: "Account Setup", icon: "envelope.fill"),
    SignupStep(id: 3, title: "Choose Plan", icon: "creditcard.fill"),
    SignupStep(id: 4, title: "Welcome!", icon: "sparkles")
]

struct SignupFunnelView: View {
    @State private var currentStep = 1
    @State private var firstName = "John"
    @State private var lastName = "Doe"
    @State private var email = "john.doe@example.com"
    @State private var password = "password"
    @State private var confirmPassword = "password"
    @State private var selectedPlan: Plan = .starter
    @State private var agreeToTerms = false
    
    @State private var errors: [String: String] = [:]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Progress Header
                ProgressHeader(currentStep: currentStep, steps: STEPS)
                    .padding(.top)

                ScrollView {
                    VStack(spacing: 24) {
                        renderStep()
                    }
                    .padding()
                }

                // Navigation
                if currentStep < 4 {
                    HStack {
                        if currentStep > 1 {
                            Button(action: prevStep) {
                                HStack {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .foregroundColor(.gray)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
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
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                } else {
                    Button(action: handleRestart) {
                        Text("Restart")
                            .underline()
                            .foregroundColor(.blue)
                    }
                    .padding()
                }
            }
            .navigationTitle("Sign Up")
            .onAppear {
                trackStepViewed()
            }
        }
    }
    
    @ViewBuilder
    private func renderStep() -> some View {
        switch currentStep {
        case 1:
            PersonalInfoStep(firstName: $firstName, lastName: $lastName, errors: errors)
        case 2:
            AccountSetupStep(email: $email, password: $password, confirmPassword: $confirmPassword, errors: errors)
        case 3:
            PlanSelectionStep(selectedPlan: $selectedPlan, agreeToTerms: $agreeToTerms, errors: errors)
        case 4:
            WelcomeStep(firstName: firstName, lastName: lastName, email: email, plan: selectedPlan)
        default:
            EmptyView()
        }
    }
    
    // Logic & Tracking
    
    private func validateStep() -> Bool {
        var newErrors: [String: String] = [:]
        
        switch currentStep {
        case 1:
            if firstName.isEmpty { newErrors["firstName"] = "First name is required" }
            if lastName.isEmpty { newErrors["lastName"] = "Last name is required" }
        case 2:
            if email.isEmpty { newErrors["email"] = "Email is required" }
            if password.isEmpty { newErrors["password"] = "Password is required" }
            if password != confirmPassword { newErrors["confirmPassword"] = "Passwords do not match" }
        case 3:
            if !agreeToTerms { newErrors["agreeToTerms"] = "You must agree to the terms" }
        default:
            break
        }
        
        self.errors = newErrors
        return newErrors.isEmpty
    }
    
    private func nextStep() {
        if validateStep() {
            switch currentStep {
            case 1:
                Altertable.shared.track(event: "Personal Info Completed", properties: ["step": 1])
            case 2:
                Altertable.shared.track(event: "Account Setup Completed", properties: ["step": 2])
            case 3:
                Altertable.shared.track(event: "Plan Selection Completed", properties: ["step": 3])
                handleSubmit()
                return
            default:
                break
            }
            
            currentStep += 1
            trackStepViewed()
        }
    }
    
    private func prevStep() {
        currentStep -= 1
        trackStepViewed()
    }
    
    private func handleSubmit() {
        Altertable.shared.track(event: "Form Submitted")
        
        let userId = UUID().uuidString
        Altertable.shared.identify(userId: userId, traits: [
            "email": email,
            "firstName": firstName,
            "lastName": lastName,
            "plan": selectedPlan.rawValue
        ])
        
        currentStep = 4
        trackStepViewed()
    }
    
    private func handleRestart() {
        Altertable.shared.track(event: "Form Restarted")
        currentStep = 1
        firstName = "John"
        lastName = "Doe"
        email = "john.doe@example.com"
        password = "password"
        confirmPassword = "password"
        selectedPlan = .starter
        agreeToTerms = false
        errors = [:]
        trackStepViewed()
    }
    
    private func trackStepViewed() {
        Altertable.shared.track(event: "Step Viewed", properties: ["step": currentStep])
    }
}

// UI Components

struct ProgressHeader: View {
    let currentStep: Int
    let steps: [SignupStep]
    
    var body: some View {
        HStack {
            ForEach(steps.indices, id: \.self) { index in
                let step = steps[index]
                VStack {
                    ZStack {
                        Circle()
                            .fill(currentStep >= step.id ? Color.blue : Color(.systemGray5))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: step.icon)
                            .foregroundColor(currentStep >= step.id ? .white : .gray)
                        
                        if currentStep > step.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .offset(x: 15, y: -15)
                                .background(Circle().fill(.white).frame(width: 15, height: 15).offset(x: 15, y: -15))
                        }
                    }
                }
                
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(currentStep > step.id ? Color.blue : Color(.systemGray5))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct PersonalInfoStep: View {
    @Binding var firstName: String
    @Binding var lastName: String
    let errors: [String: String]
    
    var body: some View {
        VStack(spacing: 20) {
            VStack {
                Text("Let's get started")
                    .font(.largeTitle)
                    .bold()
                Text("Tell us a bit about yourself")
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading) {
                Text("First Name").font(.subheadline).bold()
                TextField("Enter your first name", text: $firstName)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(errors["firstName"] != nil ? Color.red : Color.gray.opacity(0.3)))
                if let error = errors["firstName"] {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            
            VStack(alignment: .leading) {
                Text("Last Name").font(.subheadline).bold()
                TextField("Enter your last name", text: $lastName)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(errors["lastName"] != nil ? Color.red : Color.gray.opacity(0.3)))
                if let error = errors["lastName"] {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
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
                    .font(.largeTitle)
                    .bold()
                Text("Set up your login credentials")
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading) {
                Text("Email Address").font(.subheadline).bold()
                TextField("Enter your email", text: $email)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(errors["email"] != nil ? Color.red : Color.gray.opacity(0.3)))
                    .autocapitalization(.none)
                if let error = errors["email"] {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            
            VStack(alignment: .leading) {
                Text("Password").font(.subheadline).bold()
                SecureField("Create a password", text: $password)
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(errors["password"] != nil ? Color.red : Color.gray.opacity(0.3)))
                if let error = errors["password"] {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            
            VStack(alignment: .leading) {
                Text("Confirm Password").font(.subheadline).bold()
                SecureField("Confirm your password", text: $confirmPassword)
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(errors["confirmPassword"] != nil ? Color.red : Color.gray.opacity(0.3)))
                if let error = errors["confirmPassword"] {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
        }
    }
}

struct PlanSelectionStep: View {
    @Binding var selectedPlan: Plan
    @Binding var agreeToTerms: Bool
    let errors: [String: String]
    
    var body: some View {
        VStack(spacing: 20) {
            VStack {
                Text("Choose your plan")
                    .font(.largeTitle)
                    .bold()
                Text("Select the plan that works best for you")
                    .foregroundColor(.gray)
            }
            
            VStack(spacing: 12) {
                ForEach(Plan.allCases) { plan in
                    Button(action: {
                        selectedPlan = plan
                        Altertable.shared.track(event: "Plan Selected", properties: ["plan": plan.rawValue])
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(plan.title) Plan").bold()
                                Text(plan.description).font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("$\(plan.price)").bold()
                                Text("/month").font(.caption).foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(selectedPlan == plan ? Color.blue.opacity(0.1) : Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedPlan == plan ? Color.blue : Color.gray.opacity(0.2)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Toggle(isOn: $agreeToTerms.animation()) {
                Text("I agree to the Terms of Service and Privacy Policy")
                    .font(.caption)
            }
            .onChange(of: agreeToTerms) { newValue in
                Altertable.shared.track(event: "Terms Agreement Changed", properties: ["agreed": newValue, "step": 3])
            }
            
            if let error = errors["agreeToTerms"] {
                Text(error).foregroundColor(.red).font(.caption)
            }
        }
    }
}

struct WelcomeStep: View {
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
                    .font(.largeTitle)
                    .bold()
                Text("Thanks \(firstName), your account has been created successfully.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Account Summary:").bold()
                Text("Name: \(firstName) \(lastName)")
                Text("Email: \(email)")
                Text("Plan: \(plan.title)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Button(action: {
                Altertable.shared.track(event: "Get Started Clicked")
            }) {
                Text("Get Started")
                    .bold()
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
    }
}
