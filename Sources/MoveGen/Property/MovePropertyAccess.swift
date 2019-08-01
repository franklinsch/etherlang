//
//  MovePropertyAccess.swift
//  MoveGen
//
//  Created by Hails, Daniel R on 29/08/2018.
//
import AST
import MoveIR

/// Generates code for a property access.
struct MovePropertyAccess {
  var lhs: AST.Expression
  var rhs: AST.Expression
  var asLValue: Bool

  func rendered(functionContext: FunctionContext) -> MoveIR.Expression {
    let environment = functionContext.environment
    let scopeContext = functionContext.scopeContext
    let enclosingTypeName = functionContext.enclosingTypeName
    let isInStructFunction = functionContext.isInStructFunction

    var isMemoryAccess: Bool = false

    let lhsType = environment.type(of: lhs, enclosingType: enclosingTypeName, scopeContext: scopeContext)

    if case .identifier(let enumIdentifier) = lhs,
      case .identifier(let propertyIdentifier) = rhs,
      environment.isEnumDeclared(enumIdentifier.name),
      let propertyInformation = environment.property(propertyIdentifier.name, enumIdentifier.name) {
      return MoveExpression(expression: propertyInformation.property.value!).rendered(functionContext: functionContext)
    }
    if let rhsId = rhs.enclosingIdentifier {
      let lhsExpr = MoveExpression(expression: lhs).rendered(functionContext: functionContext)
      return .operation(.access(lhsExpr, rhsId.name))
    }
    print(lhs, rhs, lhsType, rhs.enclosingIdentifier)
    fatalError()
  }
}
