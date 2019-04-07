import AST
import Source
import Lexer
import Foundation

extension BoogieTranslator {
  func getCurrentFunction() -> FunctionDeclaration {
    if let behaviourDeclarationMember = currentBehaviourMember {
      switch behaviourDeclarationMember {
      case .functionDeclaration(let functionDeclaration):
        return functionDeclaration
      case .specialDeclaration(let specialDeclaration):
        return specialDeclaration.asFunctionDeclaration
      default:
        print("Error getting current function - not in a function: \(behaviourDeclarationMember.description)")
      }
    }
    print("Error getting current function - not in a current behaviour declaration")
    fatalError()
  }

  func getCurrentFunctionName() -> String? {
    if let behaviourDeclarationMember = currentBehaviourMember {
      return normaliser.getFunctionName(function: behaviourDeclarationMember, tld: getCurrentTLDName())
    }
    return nil
  }

  func addCurrentFunctionVariableDeclaration(_ vDeclaration: VariableDeclaration) {
    let name = translateIdentifierName(vDeclaration.identifier.name)
    let type = convertType(vDeclaration.type)
    // Declared local expressions don't have assigned expressions
    assert(vDeclaration.assignedExpression == nil)

    addCurrentFunctionVariableDeclaration(BVariableDeclaration(name: name,
                                                               rawName: vDeclaration.identifier.name,
                                                               type: type))
  }

  func generateStructInstanceVariableName() -> String {
    if let functionName = getCurrentFunctionName() {
      let instance = generateRandomIdentifier(prefix: "struct_instance_\(functionName)_")
      return instance
    }
    print("Cannot generate struct instance variable name, not currently in a function")
    fatalError()
  }

   func getFunctionParameters(name: String) -> [BParameterDeclaration] {
    if functionParameters[name] == nil {
      functionParameters[name] = []
    }
    return functionParameters[name]!
  }

   func setFunctionParameters(name: String, parameters: [BParameterDeclaration]) {
    functionParameters[name] = parameters
  }

   func getFunctionVariableDeclarations(name: String) -> Set<BVariableDeclaration> {
    if functionVariableDeclarations[name] == nil {
      functionVariableDeclarations[name] = Set<BVariableDeclaration>()
    }
    return functionVariableDeclarations[name]!
  }

   func setFunctionVariableDeclarations(name: String, declarations: Set<BVariableDeclaration>) {
    functionVariableDeclarations[name] = declarations
  }

   func addCurrentFunctionVariableDeclaration(_ bvDeclaration: BVariableDeclaration) {
    if let functionName = getCurrentFunctionName() {
      var variableDeclarations = getFunctionVariableDeclarations(name: functionName)
      variableDeclarations.insert(bvDeclaration)
      setFunctionVariableDeclarations(name: functionName, declarations: variableDeclarations)
    } else {
      print("Error cannot add variable declaration to function: \(bvDeclaration), not currently translating a function")
      fatalError()
    }
  }

   func generateFunctionReturnVariable() -> String {
    if let functionName = getCurrentFunctionName() {
      let returnVariable = generateRandomIdentifier(prefix: "result_variable_\(functionName)_")
      functionReturnVariableName[functionName] = returnVariable
      return returnVariable
    }
    print("Cannot generate function return variable, not currently in a function")
    fatalError()
  }

  func getFunctionReturnVariable() -> String {
    if let functionName = getCurrentFunctionName() {
      if let returnVariable = functionReturnVariableName[functionName] {
        return returnVariable
      }
      print("Could not find return variables for function \(functionName)")
      fatalError()
    }
    print("Could not find return variable not currently in a function")
    fatalError()
  }

   func getFunctionTypes(_ functionCall: FunctionCall,
                         enclosingType: RawTypeIdentifier?) -> (RawType, [RawType], Bool) {
    let currentType = enclosingType == nil ? getCurrentTLDName() : enclosingType!
    if let scopeContext = getCurrentScopeContext() {
      let callerProtections = getCurrentContractBehaviorDeclaration()?.callerProtections ?? []
      let typeStates = getCurrentContractBehaviorDeclaration()?.states ?? []
      let matchedCall = environment.matchFunctionCall(functionCall,
                                                      enclosingType: currentType,
                                                      typeStates: typeStates,
                                                      callerProtections: callerProtections,
                                                      scopeContext: scopeContext)
      var returnType: RawType
      var parameterTypes: [RawType]
      var isInit: Bool = false
      switch matchedCall {
      case .matchedFunction(let functionInformation):
        returnType = functionInformation.resultType
        parameterTypes = functionInformation.parameterTypes

      case .matchedGlobalFunction(let functionInformation):
        returnType = functionInformation.resultType
        parameterTypes = functionInformation.parameterTypes

      case .matchedFunctionWithoutCaller(let callableInformations):
        //TODO: No idea what this means
        print("Matched function without caller?")
        print(callableInformations)
        fatalError()

      case .matchedInitializer(let specialInformation):
        // Initialisers do not return values -> although struct inits do = ints
        // TODO: Assume only for struct initialisers. Need to implement for contract initialisers/fallback functions?

        // This only works for struct initialisers.
        returnType = .basicType(.int)
        parameterTypes = specialInformation.parameterTypes
        isInit = true

      case .matchedFallback(let specialInformation):
        //TODO: Handle fallback functions
        print("Handle fallback calls")
        print(specialInformation)
        fatalError()

      case .failure(let candidates):
        print("function - could not find function for call: \(functionCall)")
        print(currentType)
        print(candidates)
        fatalError()
      }

      return (returnType, parameterTypes, isInit)
    }
    print("Cannot get scopeContext from current function")
    fatalError()
  }

   func handleFunctionCall(_ functionCall: FunctionCall,
                           structInstance: BExpression? = nil,
                           owningType: String? = nil) -> (BExpression, [BStatement], [BStatement]) {
    let rawFunctionName = functionCall.identifier.name
    var argumentsExpressions = [BExpression]()
    var argumentsStatements = [BStatement]()
    var argumentPostStmts = [BStatement]()
    flintProofObligationSourceLocation[functionCall.sourceLocation.line] = functionCall.sourceLocation

    for arg in functionCall.arguments {
      let (expr, stmts, postStmts) = process(arg.expression)
      argumentsExpressions.append(expr)
      //TODO: Type of array/dict -> add those here
      //TODO if type array/dict return shadow variables - size_0, 1, 2..  + keys
      argumentsStatements += stmts
      argumentPostStmts += postStmts
    }

    switch rawFunctionName {
    // Special case to handle assert functions
    case "assert":
      // assert that assert function call always has one argument
      assert (argumentsExpressions.count == 1)
      let flintLine = functionCall.identifier.sourceLocation.line
      flintProofObligationSourceLocation[flintLine] = functionCall.sourceLocation
      argumentsStatements.append(.assertStatement(BProofObligation(expression: argumentsExpressions[0],
                                                                   mark: flintLine,
                                                                   obligationType: .assertion)))
      return (.nop, argumentsStatements, argumentPostStmts)

    // Handle fatal error case
    case "fatalError":
      argumentsStatements.append(.assume(.boolean(false)))
      return (.nop, argumentsStatements, argumentPostStmts)

    case "send":
      // send calls should have 2 arguments:
      // send(account, &w)
      assert (argumentsExpressions.count == 2)

      // Call Boogie send function
      let functionCall = BStatement.callProcedure([],
                                                  "send",
                                                  argumentsExpressions,
                                                  functionCall.sourceLocation)
      return (.nop, [functionCall], argumentPostStmts)
    default: break
    }

    // TODO: Assert that contract invariant holds
    // TODO: Need to link the failing assert to the invariant =>
    //  error msg: Can't call function, the contract invariant does not hold at this point
    //argumentsStatements += (tldInvariants[getCurrentTLDName()] ?? []).map({ .assertStatement($0) })

    let (returnType, parameterTypes, isInit) = getFunctionTypes(functionCall, enclosingType: owningType)
    let functionName: String

    if isInit {
      // When calling struct constructors, need to identify this special
      // function call and set the owning type to the Struct
      functionName = normaliser.translateGlobalIdentifierName("init" + normaliser.flattenTypes(types: parameterTypes),
                                                              tld: rawFunctionName)
    } else {
      functionName = normaliser.translateGlobalIdentifierName(rawFunctionName + normaliser.flattenTypes(types: parameterTypes),
                                                              tld: owningType ?? getCurrentTLDName())
    }

    if let instance = structInstance, !isInit {
      // instance to pass as first argument
      argumentsExpressions.insert(instance, at: 0)
    }

    if returnType != RawType.basicType(.void) {
      // Function returns a value
      let returnValueVariable = generateRandomIdentifier(prefix: "v_") // Variable to hold return value
      let returnValue = BExpression.identifier(returnValueVariable)
      let functionCall = BStatement.callProcedure([returnValueVariable],
                                                   functionName,
                                                   argumentsExpressions,
                                                   functionCall.sourceLocation)
      addCurrentFunctionVariableDeclaration(BVariableDeclaration(name: returnValueVariable,
                                                                 rawName: returnValueVariable,
                                                                 type: convertType(returnType)))
      argumentsStatements.append(functionCall)
      return (returnValue, argumentsStatements, [])
    } else {
      // Function doesn't return a value
      // Can assume can't be called as part of a nested expression,
      // has return type Void
      argumentsStatements.append(.callProcedure([], functionName, argumentsExpressions, functionCall.sourceLocation))
      return (.nop, argumentsStatements, argumentPostStmts)
    }
  }

  private func getIterableTypeDepth(type: RawType, depth: Int = 0) -> Int {
    switch type {
    case .arrayType(let type): return getIterableTypeDepth(type: type, depth: depth+1)
    case .dictionaryType(_, let valueType): return getIterableTypeDepth(type: valueType, depth: depth+1)
    case .fixedSizeArrayType(let type, _): return getIterableTypeDepth(type: type, depth: depth+1)
    default:
      return depth
    }
  }

   func process(_ functionDeclaration: FunctionDeclaration,
                isStructInit: Bool = false,
                isContractInit: Bool = false,
                callerProtections: [CallerProtection] = [],
                callerBinding: Identifier? = nil
                ) -> BTopLevelDeclaration {
    let currentFunctionName = getCurrentFunctionName()!
    let body = functionDeclaration.body
    let parameters = functionDeclaration.signature.parameters
    var signature = functionDeclaration.signature
    var returnName = signature.resultType == nil ? nil : generateFunctionReturnVariable()
    var returnType = signature.resultType == nil ? nil : convertType(signature.resultType!)
    let oldCtx = setCurrentScopeContext(functionDeclaration.scopeContext)

    let callers = callerProtections.filter({ !$0.isAny }).map({ $0.identifier })

    // Process caller capabilities
    // Need the caller preStatements to handle the case when a function is called
    let (callerPreConds, callerPreStatements) = processCallerCapabilities(callers, callerBinding)


    var bParameters = [BParameterDeclaration]()
    bParameters += parameters.flatMap({x in process(x)})
    setFunctionParameters(name: currentFunctionName, parameters: bParameters)
    var prePostConditions = [BProofObligation]()
    // TODO: Handle += operators and function calls in pre conditions
    for condition in signature.prePostConditions {
      switch condition {
      case .pre(let e):
        prePostConditions.append(BProofObligation(expression: process(e).0,
                                                  mark: e.sourceLocation.line,
                                                  obligationType: .preCondition))
        flintProofObligationSourceLocation[e.sourceLocation.line] = e.sourceLocation
      case .post(let e):
        prePostConditions.append(BProofObligation(expression: process(e).0,
                                                  mark: e.sourceLocation.line,
                                                  obligationType: .postCondition))
        flintProofObligationSourceLocation[e.sourceLocation.line] = e.sourceLocation
      }
    }

    var functionPostAmble = [BStatement]()
    var functionPreAmble = [BStatement]()

    if isContractInit {
      functionPostAmble += contractConstructorInitialisations[getCurrentTLDName()] ?? []
    }

    if let cTld = currentTLD {
      switch cTld {
      case .structDeclaration:
       self.structInstanceVariableName = generateStructInstanceVariableName()
       if isStructInit {
         returnType = .int
         returnName = generateFunctionReturnVariable()

         let nextInstance = normaliser.generateStructInstanceVariable(structName: getCurrentTLDName())

         addCurrentFunctionVariableDeclaration(BVariableDeclaration(name: self.structInstanceVariableName!,
                                                                    rawName: self.structInstanceVariableName!,
                                                                    type: .int))
         let reserveNextStructInstance: [BStatement] = [
           .assignment(.identifier(self.structInstanceVariableName!), .identifier(nextInstance)),
           .assignment(.identifier(nextInstance), .add(.identifier(nextInstance), .integer(1)))
         ]
         // Include nextInstance in modifies
         var nextInstanceId = Identifier(name: "nextInstance", //TODO: Work out how to get raw name
                                         sourceLocation: functionDeclaration.sourceLocation)
         nextInstanceId.enclosingType = getCurrentTLDName()
         signature.mutates.append(nextInstanceId)

         let returnAllocatedStructInstance: [BStatement] = [
           .assignment(.identifier(returnName!), .identifier(self.structInstanceVariableName!)),
           //.returnStatement
         ]

         let structInitPost: BExpression =
           .equals(.identifier(nextInstance), .add(.old(.identifier(nextInstance)), .integer(1)))

         prePostConditions.append(BProofObligation(expression: structInitPost,
                                                   mark: functionDeclaration.sourceLocation.line,
                                                   obligationType: .postCondition))
         flintProofObligationSourceLocation[functionDeclaration.sourceLocation.line] = functionDeclaration.sourceLocation

         functionPreAmble += reserveNextStructInstance
         functionPostAmble += returnAllocatedStructInstance
       } else {
         bParameters.append(BParameterDeclaration(name: self.structInstanceVariableName!,
                                                  rawName: self.structInstanceVariableName!,
                                                  type: .int))
       }
      default: break
       }
    }

    let bStatements = functionPreAmble + body.flatMap({x in process(x)}) + functionPostAmble

    // Procedure must hold invariant
    let invariants = (tldInvariants[getCurrentTLDName()] ?? [])
      // drop contract invariants, if init function
      .filter({ !(isContractInit || isStructInit) || ($0.obligationType != .preCondition) }) + structInvariants
    prePostConditions += invariants

    var modifies = [String]()
    for mutates in functionDeclaration.mutates {
      let enclosingType = mutates.enclosingType ?? getCurrentTLDName()
      let variableType = environment.type(of: mutates.name, enclosingType: enclosingType)
      switch variableType {
      case .arrayType, .dictionaryType:
        let depthMax = getIterableTypeDepth(type: variableType)
        for depth in 0..<depthMax {
          modifies.append(normaliser.getShadowArraySizePrefix(depth: depth) + normaliser.translateGlobalIdentifierName(mutates.name, tld: enclosingType))
          if case .dictionaryType = variableType {
            modifies.append(normaliser.getShadowDictionaryKeysPrefix(depth: depth) + normaliser.translateGlobalIdentifierName(mutates.name, tld: enclosingType))
          }
        }
      default:
        break
      }

      modifies.append(normaliser.translateGlobalIdentifierName(mutates.name, tld: enclosingType))
    }
    // Get the global shadow variables, the function modifies (but can't be directly expressed by the user) - ie. nextInstance_struct
    modifies += (functionModifiesShadow[currentFunctionName] ?? [])

    if isContractInit {
      modifies += contractGlobalVariables[getCurrentTLDName()] ?? []
    }

    if isStructInit {
      modifies += structGlobalVariables[getCurrentTLDName()] ?? []
    }

    let modifiesClauses = Set<BModifiesDeclaration>(modifies.map({
       BModifiesDeclaration(variable: $0)
    }))

    // About to exit function, reset struct instance variable
    self.structInstanceVariableName = nil
    _ = setCurrentScopeContext(oldCtx)

    // Allow us to identify failing functions
    flintProofObligationSourceLocation[functionDeclaration.sourceLocation.line] = functionDeclaration.sourceLocation
    return .procedureDeclaration(BProcedureDeclaration(
      name: currentFunctionName,
      returnType: returnType,
      returnName: returnName,
      parameters: bParameters,
      prePostConditions: callerPreConds + prePostConditions,
      modifies: modifiesClauses,
      statements: callerPreStatements + bStatements,
      variables: getFunctionVariableDeclarations(name: currentFunctionName),
      sourceLocation: functionDeclaration.sourceLocation
    ))
  }
}
