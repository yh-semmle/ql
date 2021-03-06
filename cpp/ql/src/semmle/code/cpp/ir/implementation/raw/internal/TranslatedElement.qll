import cpp
import semmle.code.cpp.ir.implementation.raw.IR
private import semmle.code.cpp.ir.implementation.Opcode
private import semmle.code.cpp.ir.internal.TempVariableTag
private import InstructionTag
private import TranslatedCondition
private import TranslatedFunction
private import TranslatedStmt

/**
 * Gets the built-in `int` type.
 */
Type getIntType() {
  result.(IntType).isImplicitlySigned()
}

/**
 * If `expr` is a conversion, gets the expression being converted. Otherwise,
 * returns `expr`.
 */
private Expr getUnconvertedExpr(Expr expr) {
  if expr instanceof Conversion then (
    result = getUnconvertedExpr(expr.(Conversion).getExpr())
  ) else (
    result = expr
  )
}

/**
 * Gets the "real" parent of `expr`. This predicate treats conversions as if
 * they were explicit nodes in the expression tree, rather than as implicit
 * nodes as in the regular AST representation.
 */
private Element getRealParent(Expr expr) {
  if expr.hasConversion() then (
    // The expression has a conversion, so treat that as its parent
    result = expr.getConversion()
  )
  else (
    // Either the expression is a top-level conversion, or it's not a
    // conversion. The real parent is the parent of the original unconverted
    // expression.
    result = getUnconvertedExpr(expr).getParent() or
    // The parent of a DestructorDestruction is the destructor itself.
    result.(Destructor).getADestruction() = expr
  )
}

/**
 * Holds if `expr` and all of its descendants should be ignored for the purposes
 * of IR generation due to some property of `expr` itself. Unlike
 * `ignoreExpr()`, this predicate does not ignore an expression solely because
 * it is a descendant of an ignored element.
 */
private predicate ignoreExprAndDescendants(Expr expr) {
  // Ignore parentless expressions
  not exists(getRealParent(expr)) or
  // Ignore the constants in SwitchCase, since their values are embedded in the
  // CaseEdge.
  getRealParent(expr) instanceof SwitchCase or
  // Ignore descendants of constant expressions, since we'll just substitute the
  // constant value.
  getRealParent(expr).(Expr).isConstant() or
  // The `DestructorCall` node for a `DestructorFieldDestruction` has a `FieldAccess`
  // node as its qualifier, but that `FieldAccess` does not have a child of its own.
  // We'll ignore that `FieldAccess`, and supply the receiver as part of the calling
  // context, much like we do with constructor calls.
  expr.getParent().(DestructorCall).getParent() instanceof DestructorFieldDestruction or
  exists(NewArrayExpr newExpr |
    // REVIEW: Ignore initializers for `NewArrayExpr` until we determine how to
    // represent them.
    newExpr.getInitializer().getFullyConverted() = expr
  )
}

/**
 * Holds if `expr` (not including its descendants) should be ignored for the
 * purposes of IR generation.
 */
private predicate ignoreExprOnly(Expr expr) {
  exists(NewOrNewArrayExpr newExpr |
    // Ignore the allocator call, because we always synthesize it. Don't ignore
    // its arguments, though, because we use them as part of the synthesis.
    newExpr.getAllocatorCall() = expr
  )
}

/**
 * Holds if `expr` should be ignored for the purposes of IR generation.
 */
private predicate ignoreExpr(Expr expr) {
  ignoreExprOnly(expr) or
  ignoreExprAndDescendants(getRealParent*(expr))
}

/**
 * Holds if `expr` is most naturally evaluated as control flow, rather than as
 * a value.
 */
private predicate isNativeCondition(Expr expr) {
  expr instanceof BinaryLogicalOperation and
  not expr.isConstant()
}

/**
 * Holds if `expr` can be evaluated as either a condition or a value expression,
 * depending on context.
 */
private predicate isFlexibleCondition(Expr expr) {
  (
    expr instanceof ParenthesisExpr or
    expr instanceof NotExpr
  ) and
  usedAsCondition(expr) and
  not expr.isConstant()
}

/**
 * Holds if `expr` is used in a condition context, i.e. the Boolean result of
 * the expression is directly used to determine control flow.
 */
private predicate usedAsCondition(Expr expr) {
  exists(BinaryLogicalOperation op |
    op.getLeftOperand().getFullyConverted() = expr or
    op.getRightOperand().getFullyConverted() = expr
  ) or
  exists(Loop loop |
    loop.getCondition().getFullyConverted() = expr
  ) or
  exists(IfStmt ifStmt |
    ifStmt.getCondition().getFullyConverted() = expr
  ) or
  exists(ConditionalExpr condExpr |
    condExpr.getCondition().getFullyConverted() = expr
  ) or
  exists(NotExpr notExpr |
    notExpr.getOperand().getFullyConverted() = expr and
    usedAsCondition(notExpr)
  ) or
  exists(ParenthesisExpr paren |
    paren.getExpr() = expr and
    usedAsCondition(paren)
  )
}

/**
 * Holds if `expr` has an lvalue-to-rvalue conversion that should be ignored
 * when generating IR. This occurs for conversion from an lvalue of function type
 * to an rvalue of function pointer type. The conversion is represented in the
 * AST as an lvalue-to-rvalue conversion, but the IR represents both a function
 * lvalue and a function pointer prvalue the same.
 */
predicate ignoreLoad(Expr expr) {
  expr.hasLValueToRValueConversion() and
  (
    expr instanceof ThisExpr or
    expr instanceof FunctionAccess or
    expr.(PointerDereferenceExpr).getOperand().getFullyConverted().getType().
      getUnspecifiedType() instanceof FunctionPointerType or
    expr.(ReferenceDereferenceExpr).getExpr().getType().
      getUnspecifiedType() instanceof FunctionReferenceType
  )
}

newtype TTranslatedElement =
  // An expression that is not being consumed as a condition
  TTranslatedValueExpr(Expr expr) {
    not ignoreExpr(expr) and
    not isNativeCondition(expr) and
    not isFlexibleCondition(expr)
  } or
  // A separate element to handle the lvalue-to-rvalue conversion step of an
  // expression.
  TTranslatedLoad(Expr expr) {
    not ignoreExpr(expr) and
    not isNativeCondition(expr) and
    not isFlexibleCondition(expr) and
    expr.hasLValueToRValueConversion() and
    not ignoreLoad(expr)
  } or
  // An expression most naturally translated as control flow.
  TTranslatedNativeCondition(Expr expr) {
    not ignoreExpr(expr) and
    isNativeCondition(expr)
  } or
  // An expression that can best be translated as control flow given the context
  // in which it is used.
  TTranslatedFlexibleCondition(Expr expr) {
    not ignoreExpr(expr) and
    isFlexibleCondition(expr)
  } or
  // An expression that is not naturally translated as control flow, but is
  // consumed in a condition context. This element adapts the original element
  // to the condition context.
  TTranslatedValueCondition(Expr expr) {
    not ignoreExpr(expr) and
    not isNativeCondition(expr) and
    not isFlexibleCondition(expr) and
    usedAsCondition(expr)
  } or
  // An expression that is naturally translated as control flow, but is used in
  // a context where a simple value is expected. This element adapts the
  // original condition to the value context.
  TTranslatedConditionValue(Expr expr) {
    not ignoreExpr(expr) and
    isNativeCondition(expr) and
    not usedAsCondition(expr)
  } or
  // An expression used as an initializer.
  TTranslatedInitialization(Expr expr) {
    not ignoreExpr(expr) and
    (
      exists(Initializer init |
        init.getExpr().getFullyConverted() = expr
      ) or
      exists(ClassAggregateLiteral initList |
        initList.getFieldExpr(_).getFullyConverted() = expr
      ) or
      exists(ArrayAggregateLiteral initList |
        initList.getElementExpr(_).getFullyConverted() = expr
      ) or
      exists(ReturnStmt returnStmt |
        returnStmt.getExpr().getFullyConverted() = expr
      ) or
      exists(ConstructorFieldInit fieldInit |
        fieldInit.getExpr().getFullyConverted() = expr
      ) or
      exists(NewExpr newExpr |
        newExpr.getInitializer().getFullyConverted() = expr
      ) or
      exists(ThrowExpr throw |
        throw.getExpr().getFullyConverted() = expr
      )
    )
  } or
  // The initialization of a field via a member of an initializer list.
  TTranslatedExplicitFieldInitialization(Expr ast, Field field,
    Expr expr) {
    exists(ClassAggregateLiteral initList |
      not ignoreExpr(initList) and
      ast = initList and
      expr = initList.getFieldExpr(field).getFullyConverted()
    ) or
    exists(ConstructorFieldInit init |
      not ignoreExpr(init) and
      ast = init and
      field = init.getTarget() and
      expr = init.getExpr().getFullyConverted()
    )
  } or
  // The value initialization of a field due to an omitted member of an
  // initializer list.
  TTranslatedFieldValueInitialization(Expr ast, Field field) {
    exists(ClassAggregateLiteral initList |
      not ignoreExpr(initList) and
      ast = initList and
      initList.isValueInitialized(field)
    )
  } or
  // The initialization of an array element via a member of an initializer list.
  TTranslatedExplicitElementInitialization(
    ArrayAggregateLiteral initList, int elementIndex) {
    not ignoreExpr(initList) and
    exists(initList.getElementExpr(elementIndex))
  } or
  // The value initialization of a range of array elements that were omitted
  // from an initializer list.
  TTranslatedElementValueInitialization(ArrayAggregateLiteral initList,
    int elementIndex, int elementCount) {
    not ignoreExpr(initList) and
    isFirstValueInitializedElementInRange(initList, elementIndex) and
    elementCount = 
      getNextExplicitlyInitializedElementAfter(initList, elementIndex) -
      elementIndex
  } or
  // The initialization of a base class from within a constructor.
  TTranslatedConstructorBaseInit(ConstructorBaseInit init) {
    not ignoreExpr(init)
  } or
  // The destruction of a base class from within a destructor.
  TTranslatedDestructorBaseDestruction(DestructorBaseDestruction destruction) {
    not ignoreExpr(destruction)
  } or
  // The destruction of a field from within a destructor.
  TTranslatedDestructorFieldDestruction(DestructorFieldDestruction destruction) {
    not ignoreExpr(destruction)
  } or
  // A statement
  TTranslatedStmt(Stmt stmt) or
  // A function
  TTranslatedFunction(Function func) {
    func.hasEntryPoint() and
    not func.isFromUninstantiatedTemplate(_)
  } or
  // A constructor init list
  TTranslatedConstructorInitList(Function func) {
    func.hasEntryPoint()
  } or
  // A destructor destruction list
  TTranslatedDestructorDestructionList(Function func) {
    func.hasEntryPoint()
  } or
  // A function parameter
  TTranslatedParameter(Parameter param) {
    param.getFunction().hasEntryPoint() or
    exists(param.getCatchBlock())
  } or
  // A local declaration
  TTranslatedDeclarationEntry(DeclarationEntry entry) {
    exists(DeclStmt declStmt |
      declStmt.getADeclarationEntry() = entry
    )
  } or
  // An allocator call in a `new` or `new[]` expression
  TTranslatedAllocatorCall(NewOrNewArrayExpr newExpr) {
    not ignoreExpr(newExpr)
  } or
  // An allocation size for a `new` or `new[]` expression
  TTranslatedAllocationSize(NewOrNewArrayExpr newExpr) {
    not ignoreExpr(newExpr)
  }

/**
 * Gets the index of the first explicitly initialized element in `initList`
 * whose index is greater than `afterElementIndex`. If there are no remaining
 * explicitly initialized elements in `initList`, the result is the total number
 * of elements in the array being initialized.
 */
 private int getNextExplicitlyInitializedElementAfter(
  ArrayAggregateLiteral initList, int afterElementIndex) {
    if exists(int x |
      x > afterElementIndex and
      exists(initList.getElementExpr(x)))
    then (
      if exists(initList.getElementExpr(afterElementIndex + 1))
      then result = afterElementIndex + 1
      else result = getNextExplicitlyInitializedElementAfter(initList, afterElementIndex+1))
    else
      result = initList.getType().getUnspecifiedType().(ArrayType).getArraySize() and
      // required for binding
      initList.isInitialized(afterElementIndex)
}

/**
 * Holds if element `elementIndex` is the first value-initialized element in a
 * range of one or more consecutive value-initialized elements in `initList`.
 */
private predicate isFirstValueInitializedElementInRange(
  ArrayAggregateLiteral initList, int elementIndex) {
  initList.isValueInitialized(elementIndex) and
  (
    elementIndex = 0 or
    not initList.isValueInitialized(elementIndex - 1)
  )
}

/**
 * Represents an AST node for which IR needs to be generated.
 *
 * In most cases, there is a single `TranslatedElement` for each AST node.
 * However, when a single AST node performs two separable operations (e.g.
 * a `VariableAccess` that is also a load), there may be multiple
 * `TranslatedElement` nodes for a single AST node.
 */
abstract class TranslatedElement extends TTranslatedElement {
  abstract string toString();

  /**
   * Gets the AST node being translated.
   */
  abstract Locatable getAST();

  /**
   * Get the first instruction to be executed in the evaluation of this element.
   */
  abstract Instruction getFirstInstruction();

  /**
   * Get the immediate child elements of this element.
   */
  final TranslatedElement getAChild() {
    result = getChild(_)
  }

  /**
   * Gets the immediate child element of this element. The `id` is unique
   * among all children of this element, but the values are not necessarily
   * consecutive.
   */
  abstract TranslatedElement getChild(int id);

  /**
   * Gets the an identifier string for the element. This string is unique within
   * the scope of the element's function.
   */
  final string getId() {
    result = getUniqueId().toString()
  }

  private TranslatedElement getChildByRank(int rankIndex) {
    result = rank[rankIndex + 1](TranslatedElement child, int id |
      child = getChild(id) |
      child order by id
    )
  }

  language[monotonicAggregates]
  private int getDescendantCount() {
    result = 1 + sum(TranslatedElement child |
      child = getChildByRank(_) |
      child.getDescendantCount()
    )
  }

  private int getUniqueId() {
    if not exists(getParent()) then 
      result = 0
    else
      exists(TranslatedElement parent |
        parent = getParent() and
        if this = parent.getChildByRank(0) then
          result = 1 + parent.getUniqueId()
        else
          exists(int childIndex, TranslatedElement previousChild |
            this = parent.getChildByRank(childIndex) and
            previousChild = parent.getChildByRank(childIndex - 1) and
            result = previousChild.getUniqueId() +
              previousChild.getDescendantCount()
          )
      )
  }

  /**
   * Holds if this element generates an instruction with opcode `opcode` and
   * result type `resultType`. `tag` must be unique for each instruction
   * generated from the same AST node (not just from the same
   * `TranslatedElement`).
   * If the instruction does not return a result, `resultType` should be
   * `VoidType`.
   */
  abstract predicate hasInstruction(Opcode opcode, InstructionTag tag,
    Type resultType, boolean isGLValue);

  /**
   * Gets the `Function` that contains this element.
   */
  abstract Function getFunction();

  /**
   * Gets the successor instruction of the instruction that was generated by
   * this element for tag `tag`. The successor edge kind is specified by `kind`.
   */
  abstract Instruction getInstructionSuccessor(InstructionTag tag,
    EdgeKind kind);

  /**
   * Gets the successor instruction to which control should flow after the
   * child element specified by `child` has finished execution.
   */
  abstract Instruction getChildSuccessor(TranslatedElement child);

  /**
   * Gets the instruction to which control should flow if an exception is thrown
   * within this element. This will generally return first `catch` block of the
   * nearest enclosing `try`, or the `Unwind` instruction for the function if
   * there is no enclosing `try`.
   */
  Instruction getExceptionSuccessorInstruction() {
    result = getParent().getExceptionSuccessorInstruction()
  }

  /**
   * Holds if this element generates a temporary variable with type `type`.
   * `tag` must be unique for each variable generated from the same AST node
   * (not just from the same `TranslatedElement`).
   */
  predicate hasTempVariable(TempVariableTag tag, Type type) {
    none()
  }

  /**
   * If the instruction specified by `tag` is a `FunctionInstruction`, gets the
   * `Function` for that instruction.
   */
  Function getInstructionFunction(InstructionTag tag) {
    none()
  }

  /**
   * If the instruction specified by `tag` is a `VariableInstruction`, gets the
   * `IRVariable` for that instruction.
   */
  IRVariable getInstructionVariable(InstructionTag tag) {
    none()
  }

  /**
   * If the instruction specified by `tag` is a `FieldInstruction`, gets the
   * `Field` for that instruction.
   */
  Field getInstructionField(InstructionTag tag) {
    none()
  }
  
  /**
   * If the instruction specified by `tag` is a `ConstantValueInstruction`, gets
   * the constant value for that instruction.
   */
  string getInstructionConstantValue(InstructionTag tag) {
    none()
  }

  /**
   * If the instruction specified by `tag` is a `PointerArithmeticInstruction`,
   * gets the size of the type pointed to by the pointer.
   */
  int getInstructionElementSize(InstructionTag tag) {
    none()
  }

  /**
   * If the instruction specified by `tag` has a result of type `UnknownType`,
   * gets the size of the result in bytes. If the result does not have a knonwn
   * constant size, this predicate does not hold.
   */
  int getInstructionResultSize(InstructionTag tag) {
    none()
  }

  /**
   * If the instruction specified by `tag` is a `StringConstantInstruction`,
   * gets the `StringLiteral` for that instruction.
   */
  StringLiteral getInstructionStringLiteral(InstructionTag tag) {
    none()
  }

  /**
   * If the instruction specified by `tag` is a `CatchByTypeInstruction`,
   * gets the type of the exception to be caught.
   */
  Type getInstructionExceptionType(InstructionTag tag) {
    none()
  }

  /**
   * If the instruction specified by `tag` is an `InheritanceConversionInstruction`,
   * gets the inheritance relationship for that instruction.
   */
  predicate getInstructionInheritance(InstructionTag tag, Class baseClass,
      Class derivedClass) {
    none()
  }

  /**
   * Gets the instruction whose result is consumed as an operand of the
   * instruction specified by `tag`, with the operand specified by `operandTag`.
   */
  Instruction getInstructionOperand(InstructionTag tag, OperandTag operandTag) {
    none()
  }

  /**
   * Gets the instruction generated by this element with tag `tag`.
   */
  final Instruction getInstruction(InstructionTag tag) {
    result.getAST() = getAST() and
    result.getTag() = tag
  }

  /**
   * Gets the temporary variable generated by this element with tag `tag`.
   */
  final IRTempVariable getTempVariable(TempVariableTag tag) {
    result.getAST() = getAST() and
    result.getTag() = tag
  }

  /**
   * Gets the parent element of this element.
   */
  final TranslatedElement getParent() {
    result.getAChild() = this
  }
}
