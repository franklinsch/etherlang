//
//  MoveContract.swift
//  MoveGen
//
//

import AST
import Lexer
import MoveIR

/// Generates code for a contract.
struct MoveContract {

  static var stateVariablePrefix = "flintState$"

  var contractDeclaration: ContractDeclaration
  var contractBehaviorDeclarations: [ContractBehaviorDeclaration]
  var structDeclarations: [StructDeclaration]
  var environment: Environment
  var externalTraitDeclarations: [TraitDeclaration]

  var externalModules: [TraitDeclaration] {
    return externalTraitDeclarations.filter { $0.isModule }
  }

  var externalStructs: [TraitDeclaration] {
    return externalTraitDeclarations.filter { $0.isStruct }
  }

  init(contractDeclaration: ContractDeclaration,
       contractBehaviorDeclarations: [ContractBehaviorDeclaration],
       structDeclarations: [StructDeclaration],
       environment: Environment,
       externalTraitDeclarations: [TraitDeclaration]) {
    self.contractDeclaration = contractDeclaration
    self.contractBehaviorDeclarations = contractBehaviorDeclarations
    self.structDeclarations = structDeclarations
    self.environment = environment
    self.externalTraitDeclarations = externalTraitDeclarations
  }

  func rendered() -> String {
    let imports: [MoveIR.Statement] = externalTraitDeclarations.compactMap { (declaration: TraitDeclaration) in
      declaration.moduleAddress.map {
        .`import`(ModuleImport(name: declaration.identifier.name, address: $0))
      }
    } + MoveRuntimeType.allImports
    let renderedImports = MoveIR.Statement.renderStatements(statements: imports)

    // Generate code for each function in the contract.
    let functions = contractBehaviorDeclarations.flatMap { contractBehaviorDeclaration in
      contractBehaviorDeclaration.members.compactMap { member -> MoveFunction? in
        guard case .functionDeclaration(let functionDeclaration) = member else {
          return nil
        }

        return MoveFunction(functionDeclaration: functionDeclaration,
                            typeIdentifier: contractDeclaration.identifier,
                            typeStates: contractBehaviorDeclaration.states,
                            callerBinding: contractBehaviorDeclaration.callerBinding,
                            callerProtections: contractBehaviorDeclaration.callerProtections,
                            environment: environment)
      }
    }

    let functionsCode = functions.map { $0.rendered() }
      .joined(separator: "\n\n").indented(by: 2)

    let initializerBody = renderPublicInitializer()
    let context = FunctionContext(environment: environment,
                                  scopeContext: ScopeContext(),
                                  enclosingTypeName: contractDeclaration.identifier.name,
                                  isInStructFunction: false)

    let members = contractDeclaration.members.compactMap { (member: ContractMember) in
      switch member {
      case .variableDeclaration(let declaration):
        return MoveFieldDeclaration(variableDeclaration: declaration)
            .rendered(functionContext: context).description
      default: return nil
      }
    }.joined(separator: ",\n")

    let structs = (
        structDeclarations.map { "\n" + MoveStruct(structDeclaration: $0, environment: environment).rendered() }
            + MoveRuntimeType.allDeclarations.map { "\n" + $0 }
    ).joined(separator: "")

    // Main contract body.
    return #"""
    module \#(contractDeclaration.identifier.name) {
      \#(renderedImports.indented(by: 2))

      resource T {
        \#(members.indented(by: 4))
      }\#
      \#(structs.indented(by: 2))

      \#(initializerBody.indented(by: 2))

      //////////////////////////////////////
      //// -- User-defined functions -- ////
      //////////////////////////////////////

      \#(functionsCode)

      //////////////////////////////////////
      //// -- // ~ // Common // ~ // -- ////
      //////////////////////////////////////

      \#(renderCommon(indentedBy: 2))
    }
    """#
  }

  func renderStructFunctions() -> String {
    return structDeclarations.map { structDeclaration in
      return """
             //// \(structDeclaration.identifier.name)::\(structDeclaration.sourceLocation)  ////

             \(MoveStruct(structDeclaration: structDeclaration, environment: environment).renderCommon())
             """
    }.joined(separator: "\n\n")
  }

  func renderRuntimeFunctions() -> String {
    return MoveRuntimeFunction.allDeclarations.joined(separator: "\n\n")
  }

  func renderPublicInitializer() -> String {
    let (initializerDeclaration, contractBehaviorDeclaration) = findContractPublicInitializer()!

    let callerBinding = contractBehaviorDeclaration.callerBinding
    let callerProtections = contractBehaviorDeclaration.callerProtections

    let initializer = MoveContractInitializer(initializerDeclaration: initializerDeclaration,
                                            typeIdentifier: contractDeclaration.identifier,
                                            propertiesInEnclosingType: contractDeclaration.variableDeclarations,
                                            callerBinding: callerBinding,
                                            callerProtections: callerProtections,
                                            environment: environment,
                                            isContractFunction: true,
                                            contract: self).rendered()

    return """
    //////////////////////////////////////
    //// --      Initializer       -- ////
    //////////////////////////////////////

    \(initializer)
    """
  }

  func renderCommon(indentedBy: Int) -> String {

     let structHeader = """
     //////////////////////////////////////
     //// --    Struct Functions    -- ////
     //////////////////////////////////////
     """
     let runtimeHeader = """
     //////////////////////////////////////
     //// --     Flint Runtime      -- ////
     //// -- // -  Functions   - // -- ////
     //////////////////////////////////////
     """

     // Generate code for each function in the structs.
     let structFunctions = renderStructFunctions()

     // Generate runtime functions.
     let runtimeFunctionsDeclarations = renderRuntimeFunctions()

     return """
     \(structHeader.indented(by: indentedBy))

     \(structFunctions.indented(by: indentedBy, andFirst: true))

     \(runtimeHeader.indented(by: indentedBy, andFirst: true))

     \(runtimeFunctionsDeclarations.indented(by: indentedBy, andFirst: true))
     """
   }

  /// Finds the contract's public initializer, if any is declared,
  /// and returns the enclosing contract behavior declaration.
  func findContractPublicInitializer() -> (SpecialDeclaration, ContractBehaviorDeclaration)? {
    let result = contractBehaviorDeclarations.flatMap { contractBehaviorDeclaration in
      return contractBehaviorDeclaration.members.compactMap { member ->
        (SpecialDeclaration, ContractBehaviorDeclaration)? in
        guard case .specialDeclaration(let specialDeclaration) = member,
            specialDeclaration.isInit,
            specialDeclaration.isPublic else {
          return nil
        }
        return (specialDeclaration, contractBehaviorDeclaration)
      }
    }

    guard result.count < 2 else {
      fatalError("Too many initializers")
    }

    return result.first
  }

  /// Finds the contract's public fallback, if any is declared.
  func findContractPublicFallback() -> SpecialDeclaration? {
    let result = contractBehaviorDeclarations.flatMap { contractBehaviorDeclaration in
      return contractBehaviorDeclaration.members.compactMap { member -> SpecialDeclaration? in
        guard case .specialDeclaration(let specialDeclaration) = member,
            specialDeclaration.isFallback,
            specialDeclaration.isPublic else {
          return nil
        }
        return specialDeclaration
      }
    }

    guard result.count < 2 else {
      fatalError("Too many fallbacks")
    }

    return result.first
  }
}
