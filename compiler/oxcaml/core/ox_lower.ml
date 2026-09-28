(* Native semantic port of compiler/lower.bend.

   Source SHA-256: 76e6fc0a4e99093e42758ce5a5bd443f20a26f068fa2d0d5bfc1e5ab7ee2e2f9

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module CoreTypes = Ox_types

module C = Ox_cst

module Postfix = Ox_postfix

module T = Ox_source_types

module A = Ox_source_arguments

module O = Ox_operators

module Index = Ox_index

module Families = Ox_effect_families

module D = Ox_dependency

module Closures = Ox_closures

type t_Local =
  | Local of Base.text * Base.text
and t_GlobalKind =
  | ConstantName
  | FunctionName
  | ConstructorName
  | RecordConstructorName of (Base.text) list
  | OperationName of M.t_TypeId
  | OperationTemplateName of M.t_TypeId * (A.t_Pattern) list
  | EffectFamilyName of (M.t_TypeId) list * (A.t_Pattern) list
and t_Global =
  | Global of Base.text * Base.text * t_GlobalKind
and t_Context =
  | Context of (t_Global) Base.map * (T.t_Header) Base.map * (O.t_Fixity) list * (t_Local) list * (int) option * (T.t_Variable) list
and t_NodeKind =
  | Wrapper
  | Integer
  | Float
  | PrefixNode
  | Truth
  | Falsehood
  | Name
  | Intrinsic
  | ValueDeclaration
  | DataNode
  | EffectNode
  | EffectTypeNode
  | SymbolicFixity
  | NamedFixity
  | GroupNode
  | ArrayNode
  | RecordNode
  | ApplicationNode
  | MemberNode
  | IndexNode
  | InfixNode
  | LambdaNode
  | CaseNode
  | Block
  | Binding
  | Rebinding
  | ForLoop
  | EffectBinding
  | Return
  | Conditional
  | PatternConditional
  | PatternWrapper
  | PatternGroup
  | PatternConstructor
  | PatternConstructorForm of (C.t_Cst) list
  | PatternPayload
  | PatternChildren
  | PatternElements of (M.t_Pattern) list * (t_Local) list
  | PatternRecordFields of Base.text * (Base.text) list * (M.t_Pattern) Base.map * (t_Local) list
  | PatternName
  | PatternValue
  | Unsupported
and t_Primitive =
  | AssociatedPrimitive
  | DeferredPrimitive of Base.text * int
  | EffectFamilyPrimitive of Base.text * int * int
  | ScalarPrimitive of M.t_ScalarOp
  | UnaryPrimitive of M.t_UnaryOp
  | ProviderPrimitive
  | StateProviderPrimitive
  | OperationDescriptorPrimitive
  | FunctionEffectsPrimitive
  | EffectHasPrimitive
  | EffectCountPrimitive
  | EffectSamePrimitive
  | PanicPrimitive
  | ProjectPrimitive
  | ArrayGeneratePrimitive
  | ArrayFillPrimitive
  | ArrayGetPrimitive
  | ArraySetPrimitive
  | ArrayLengthPrimitive
and t_RecordTarget =
  | RecordTarget of Base.text * (Base.text) list
and t_RecordElement =
  | RecordElement of Base.text * Base.text * M.t_Expr
and t_TypedArguments =
  | TypedArguments of (M.t_Ty) list * (C.t_Cst) list
and t_TypedCall =
  | TypedCall of M.t_Expr * (C.t_Cst) list
and t_TemplateReference =
  | TemplateReference of M.t_TypeId * (A.t_Pattern) list
and t_OperationTarget =
  | OperationTarget of M.t_TypeId * (M.t_TypeId) option * (M.t_Ty) list
and t_Work =
  | Expression of t_NodeKind * C.t_Cst
  | Group of (C.t_Cst) list * int
  | ProductElements of (C.t_Cst) list * (M.t_Expr) list * int
  | ArrayElements of (C.t_Cst) list * (M.t_Expr) list * int
  | RecordElements of Base.text * (Base.text) list * (C.t_Cst) list * (t_RecordElement) list * Base.set * C.t_Cst
  | Arguments of M.t_Expr * (C.t_Cst) list * int
  | UpdatePath of M.t_Expr * (C.t_Cst) list * C.t_Cst * int
  | UpdateSelector of Base.text * M.t_Expr * C.t_Cst * (C.t_Cst) list * C.t_Cst * int
  | ApplicationHead of t_NodeKind * C.t_Cst * (C.t_Cst) list * int
  | GroupedApplication of (t_TypedCall) option * t_NodeKind * C.t_Cst * (C.t_Cst) list * int
  | RecordApplication of (t_TemplateReference) option * C.t_Cst * C.t_Cst * (C.t_Cst) list * int * C.t_Cst
  | ApplicationTemplate of (t_TemplateReference) option * C.t_Cst * (C.t_Cst) list * int
  | PrimitiveCall of t_Primitive * C.t_Cst * (C.t_Cst) list * int
  | DescriptorOperation of bool * C.t_Cst * int
  | DescriptorArgument of bool * C.t_Cst
  | InfixTails of M.t_Expr * (C.t_Cst) list * (O.t_Tail) list
  | CaseValues of (C.t_Cst) list * (M.t_Expr) list * (C.t_Cst) list
  | Arms of (M.t_Expr) list * (C.t_Cst) list * ((M.t_Expr) M.t_MatchArm) list
  | ResolvedBlock of (C.t_Cst) list * M.t_Expr * int
  | ForStart of bool * C.t_Cst * M.t_Pattern * M.t_Expr * M.t_Expr * Base.text
  | ForRange of (C.t_Cst) list * M.t_Pattern * M.t_Expr * M.t_Expr * M.t_Expr * Base.text * int
  | Statements of (C.t_Cst) list * (t_Local) list
  | Statement of t_NodeKind * C.t_Cst * (C.t_Cst) list * (t_Local) list
and t_Parameter =
  | Parameter of Base.text * Base.text * (M.t_Ty) option
and t_PatternResult =
  | PatternResult of M.t_Pattern * (t_Local) list
and t_PatternRow =
  | PatternRow of (M.t_Pattern) list * (t_Local) list
and t_GlobalPrefix =
  | GlobalPrefix of t_Global * (C.t_Cst) list
and t_ConstraintKind =
  | AssociatedConstraint
  | ReceiverConstraint
  | FieldConstraint
  | UpdateConstraint
  | OperationConstraint
  | TypeRepConstraint
  | EffectRepConstraint
  | UnknownConstraint
and t_LoopTargetsWork =
  | LoopTargets of (C.t_Cst) list
  | LoopTarget of t_NodeKind * C.t_Cst * (C.t_Cst) list
and t_GroupedOperation =
  | OperationHead of t_NodeKind * C.t_Cst
  | OperationChildren of (C.t_Cst) list
  | OperationTemplate of (t_TemplateReference) option * C.t_Cst
and t_AnnotationScan =
  | ScanNode of C.t_Cst * bool
  | ScanNodes of (C.t_Cst) list * (C.t_Cst) list
and t_DeclarationInitializer =
  | InitializerNode of t_NodeKind * C.t_Cst
  | InitializerChildren of (C.t_Cst) list
and t_DeclarationBatch =
  | DeclarationLeaf of (C.t_Cst) list
  | DeclarationFork of t_DeclarationBatch * t_DeclarationBatch
and t_WeightedDeclaration =
  | WeightedDeclaration of C.t_Cst * int
and t_CostNode =
  | CostNode of C.t_Cst * ((C.t_Cst) list) list
and t_Prelude =
  | Prelude of M.t_Module * t_Context
and t_SourcePlan =
  | SourcePlan of M.t_Module * t_Context * (C.t_Cst) list

let s_0 = Base.text_of_utf8 "INTEGER"

let s_1 = Base.text_of_utf8 "INTRINSIC"

let s_2 = Base.text_of_utf8 "IDENT"

let s_3 = Base.text_of_utf8 "FLOAT"

let s_4 = Base.text_of_utf8 "False"

let s_5 = Base.text_of_utf8 "True"

let s_6 = Base.text_of_utf8 "atom"

let s_7 = Base.text_of_utf8 "array"

let s_8 = Base.text_of_utf8 "application"

let s_9 = Base.text_of_utf8 "binding"

let s_10 = Base.text_of_utf8 "call_expression"

let s_11 = Base.text_of_utf8 "case_expression"

let s_12 = Base.text_of_utf8 "conditional"

let s_13 = Base.text_of_utf8 "constructor_pattern"

let s_14 = Base.text_of_utf8 "data_type"

let s_15 = Base.text_of_utf8 "do_block"

let s_16 = Base.text_of_utf8 "ever_statement"

let s_17 = Base.text_of_utf8 "expression"

let s_18 = Base.text_of_utf8 "effect_binding"

let s_19 = Base.text_of_utf8 "effect_step"

let s_20 = Base.text_of_utf8 "effect_declaration"

let s_21 = Base.text_of_utf8 "effect_type"

let s_22 = Base.text_of_utf8 "for_statement"

let s_23 = Base.text_of_utf8 "group"

let s_24 = Base.text_of_utf8 "infix_expression"

let s_25 = Base.text_of_utf8 "index_expression"

let s_26 = Base.text_of_utf8 "lambda"

let s_27 = Base.text_of_utf8 "member_expression"

let s_28 = Base.text_of_utf8 "named_fixity"

let s_29 = Base.text_of_utf8 "prefix_expression"

let s_30 = Base.text_of_utf8 "pattern_conditional"

let s_31 = Base.text_of_utf8 "pattern"

let s_32 = Base.text_of_utf8 "pattern_group"

let s_33 = Base.text_of_utf8 "value_pattern"

let s_34 = Base.text_of_utf8 "value_declaration"

let s_35 = Base.text_of_utf8 "qualified_name"

let s_36 = Base.text_of_utf8 "range_statement"

let s_37 = Base.text_of_utf8 "record"

let s_38 = Base.text_of_utf8 "result"

let s_39 = Base.text_of_utf8 "rebinding"

let s_40 = Base.text_of_utf8 "symbolic_fixity"

let s_41 = Base.text_of_utf8 "effect_member"

let s_42 = Base.text_of_utf8 "effect family requires an operation member"

let s_43 = Base.text_of_utf8 "unknown_value"

let s_44 = Base.text_of_utf8 "unknown value: "

let s_45 = Base.text_of_utf8 "."

let s_46 = Base.text_of_utf8 ""

let s_47 = Base.text_of_utf8 "internal_cst"

let s_48 = Base.text_of_utf8 "qualified name has no root"

let s_49 = Base.text_of_utf8 "type_arity"

let s_50 = Base.text_of_utf8 "generic effect operation requires exactly one type parameter"

let s_51 = Base.text_of_utf8 "operation_target"

let s_52 = Base.text_of_utf8 "expected a declared parameterized effect operation"

let s_53 = Base.text_of_utf8 "expected a declared parameterized effect operation name"

let s_54 = Base.text_of_utf8 "effect_family"

let s_55 = Base.text_of_utf8 "read and write operations must belong to the same declared effect family"

let s_56 = Base.text_of_utf8 "unknown_effect"

let s_57 = Base.text_of_utf8 "effect rows require Foreign or a declared effect operation or family"

let s_58 = Base.text_of_utf8 "Foreign"

let s_59 = Base.text_of_utf8 "effect operation requires another type argument"

let s_60 = Base.text_of_utf8 "Unit"

let s_61 = Base.text_of_utf8 "U32"

let s_62 = Base.text_of_utf8 "F32"

let s_63 = Base.text_of_utf8 "Bool"

let s_64 = Base.text_of_utf8 "Array"

let s_65 = Base.text_of_utf8 "value"

let s_66 = Base.text_of_utf8 "head"

let s_67 = Base.text_of_utf8 "arguments"

let s_68 = Base.text_of_utf8 "elements"

let s_69 = Base.text_of_utf8 "fields"

let s_70 = Base.text_of_utf8 "name"

let s_71 = Base.text_of_utf8 "tails"

let s_72 = Base.text_of_utf8 "operator"

let s_73 = Base.text_of_utf8 "too many effect type arguments"

let s_74 = Base.text_of_utf8 "unknown_constructor"

let s_75 = Base.text_of_utf8 "unknown record constructor: "

let s_76 = Base.text_of_utf8 "record_constructor"

let s_77 = Base.text_of_utf8 "named fields require a declared record constructor"

let s_78 = Base.text_of_utf8 "unknown_record_field"

let s_79 = Base.text_of_utf8 "record has no field named "

let s_80 = Base.text_of_utf8 "duplicate_record_field"

let s_81 = Base.text_of_utf8 "record field is supplied more than once: "

let s_82 = Base.text_of_utf8 "parser"

let s_83 = Base.text_of_utf8 "invalid record declaration fields"

let s_84 = Base.text_of_utf8 "invalid record field value"

let s_85 = Base.text_of_utf8 "missing_record_field"

let s_86 = Base.text_of_utf8 "missing record field: "

let s_87 = Base.text_of_utf8 "_"

let s_88 = Base.text_of_utf8 "self"

let s_89 = Base.text_of_utf8 "unknown_rebinding"

let s_90 = Base.text_of_utf8 ":= requires an existing local binding: "

let s_91 = Base.text_of_utf8 "internal_error"

let s_92 = Base.text_of_utf8 "rebinding scope lost self"

let s_93 = Base.text_of_utf8 "$"

let s_94 = Base.text_of_utf8 "$predicate$"

let s_95 = Base.text_of_utf8 "invalid_constraint"

let s_96 = Base.text_of_utf8 "a predicate has more than one invocation row"

let s_97 = Base.text_of_utf8 "this predicate does not accept an invocation row"

let s_98 = Base.text_of_utf8 "this predicate needs one quoted member name"

let s_99 = Base.text_of_utf8 "operation predicate needs a qualified operation name"

let s_100 = Base.text_of_utf8 "$operation$"

let s_101 = Base.text_of_utf8 "operation predicate needs a declared generic effect operation"

let s_102 = Base.text_of_utf8 "operation predicate needs an effect operation name"

let s_103 = Base.text_of_utf8 "associated"

let s_104 = Base.text_of_utf8 "receiver"

let s_105 = Base.text_of_utf8 "field"

let s_106 = Base.text_of_utf8 "update"

let s_107 = Base.text_of_utf8 "operation"

let s_108 = Base.text_of_utf8 "type_rep"

let s_109 = Base.text_of_utf8 "effect_rep"

let s_110 = Base.text_of_utf8 "predicate has the wrong kind or number of type arguments"

let s_111 = Base.text_of_utf8 "predicate has the wrong argument shape"

let s_112 = Base.text_of_utf8 "this predicate does not accept a member name"

let s_113 = Base.text_of_utf8 "member"

let s_114 = Base.text_of_utf8 "effects"

let s_115 = Base.text_of_utf8 "effect_instance"

let s_116 = Base.text_of_utf8 "unsupported_polymorphic_effect_label"

let s_117 = Base.text_of_utf8 "explicit predicate rows currently require concrete effect operation labels"

let s_118 = Base.text_of_utf8 "kind"

let s_119 = Base.text_of_utf8 "where requires a complete binding type annotation"

let s_120 = Base.text_of_utf8 "predicates"

let s_121 = Base.text_of_utf8 "where"

let s_122 = Base.text_of_utf8 "expected where before predicate block"

let s_123 = Base.text_of_utf8 "marker"

let s_124 = Base.text_of_utf8 "invalid where clause field"

let s_125 = Base.text_of_utf8 "$unit"

let s_126 = Base.text_of_utf8 "invalid parameter"

let s_127 = Base.text_of_utf8 "higher_rank_constraint"

let s_128 = Base.text_of_utf8 "where clauses are supported on bindings, not parameter annotations"

let s_129 = Base.text_of_utf8 "annotation"

let s_130 = Base.text_of_utf8 "@u32.add"

let s_131 = Base.text_of_utf8 "@u32.sub"

let s_132 = Base.text_of_utf8 "@u32.mul"

let s_133 = Base.text_of_utf8 "@u32.eq"

let s_134 = Base.text_of_utf8 "@u32.lt"

let s_135 = Base.text_of_utf8 "@f32.add"

let s_136 = Base.text_of_utf8 "@f32.sub"

let s_137 = Base.text_of_utf8 "@f32.mul"

let s_138 = Base.text_of_utf8 "@f32.div"

let s_139 = Base.text_of_utf8 "@f32.eq"

let s_140 = Base.text_of_utf8 "@f32.ne"

let s_141 = Base.text_of_utf8 "@f32.lt"

let s_142 = Base.text_of_utf8 "@f32.le"

let s_143 = Base.text_of_utf8 "@f32.gt"

let s_144 = Base.text_of_utf8 "@f32.ge"

let s_145 = Base.text_of_utf8 "@f32.neg"

let s_146 = Base.text_of_utf8 "@f32.abs"

let s_147 = Base.text_of_utf8 "@f32.sqrt"

let s_148 = Base.text_of_utf8 "@f32.floor"

let s_149 = Base.text_of_utf8 "@f32.ceil"

let s_150 = Base.text_of_utf8 "@f32.trunc"

let s_151 = Base.text_of_utf8 "@u32.to_f32"

let s_152 = Base.text_of_utf8 "@f32.to_u32"

let s_153 = Base.text_of_utf8 "@panic"

let s_154 = Base.text_of_utf8 "unknown_intrinsic"

let s_155 = Base.text_of_utf8 "unknown compiler intrinsic "

let s_156 = Base.text_of_utf8 "@product.get"

let s_157 = Base.text_of_utf8 "@array.generate"

let s_158 = Base.text_of_utf8 "@array.fill"

let s_159 = Base.text_of_utf8 "@array.get"

let s_160 = Base.text_of_utf8 "@array.set"

let s_161 = Base.text_of_utf8 "@array.length"

let s_162 = Base.text_of_utf8 "@effect.state"

let s_163 = Base.text_of_utf8 "@effect.provider"

let s_164 = Base.text_of_utf8 "@effect.descriptor"

let s_165 = Base.text_of_utf8 "@effect.of"

let s_166 = Base.text_of_utf8 "@effect.has"

let s_167 = Base.text_of_utf8 "@effect.count"

let s_168 = Base.text_of_utf8 "@effect.same"

let s_169 = Base.text_of_utf8 "@effect.run"

let s_170 = Base.text_of_utf8 "@effect.reader"

let s_171 = Base.text_of_utf8 "@effect.writer"

let s_172 = Base.text_of_utf8 "@type.same"

let s_173 = Base.text_of_utf8 "@state.get"

let s_174 = Base.text_of_utf8 "@state.set"

let s_175 = Base.text_of_utf8 "@state.run"

let s_176 = Base.text_of_utf8 "@state.reader"

let s_177 = Base.text_of_utf8 "@state.writer"

let s_178 = Base.text_of_utf8 "@type.call"

let s_179 = Base.text_of_utf8 "product_index_literal"

let s_180 = Base.text_of_utf8 "product projection requires a literal zero-based index"

let s_181 = Base.text_of_utf8 "literal_required"

let s_182 = Base.text_of_utf8 "this intrinsic requires a literal string argument"

let s_183 = Base.text_of_utf8 "STRING"

let s_184 = Base.text_of_utf8 "expected the name of a declared effect operation"

let s_185 = Base.text_of_utf8 "sealed_effect"

let s_186 = Base.text_of_utf8 "Foreign is a compiler effect label, not a callable or providable operation"

let s_187 = Base.text_of_utf8 "function_target"

let s_188 = Base.text_of_utf8 "effect reflection requires a statically named top-level function"

let s_189 = Base.text_of_utf8 "unsupported_prefix"

let s_190 = Base.text_of_utf8 "only F32 prefix negation (-) is supported"

let s_191 = Base.text_of_utf8 "expected a data constructor"

let s_192 = Base.text_of_utf8 "value_pattern_reference"

let s_193 = Base.text_of_utf8 "a value pattern requires a constant, parameter, or existing let binding"

let s_194 = Base.text_of_utf8 "duplicate_pattern_binding"

let s_195 = Base.text_of_utf8 "a pattern cannot bind the same name more than once"

let s_196 = Base.text_of_utf8 "record pattern field has multiple patterns"

let s_197 = Base.text_of_utf8 "pattern exhausted its node-count bound"

let s_198 = Base.text_of_utf8 "invalid constructor pattern"

let s_199 = Base.text_of_utf8 "payload"

let s_200 = Base.text_of_utf8 "TYPE_IDENT"

let s_201 = Base.text_of_utf8 "record_pattern"

let s_202 = Base.text_of_utf8 "constructor pattern has multiple field groups"

let s_203 = Base.text_of_utf8 "unsupported_pattern"

let s_204 = Base.text_of_utf8 "unsupported pattern"

let s_205 = Base.text_of_utf8 "statements"

let s_206 = Base.text_of_utf8 "alternative"

let s_207 = Base.text_of_utf8 "invalid else field"

let s_208 = Base.text_of_utf8 "unreachable_statement"

let s_209 = Base.text_of_utf8 "statement after return in the same suite"

let s_210 = Base.text_of_utf8 "resolver_required"

let s_211 = Base.text_of_utf8 "return $ requires monad resolution, which is not implemented; provider blocks return plain values"

let s_212 = Base.text_of_utf8 "return_scope"

let s_213 = Base.text_of_utf8 "return requires an enclosing do block in this function"

let s_214 = Base.text_of_utf8 "$discard$"

let s_215 = Base.text_of_utf8 "$pattern$"

let s_216 = Base.text_of_utf8 "invalid use binding"

let s_217 = Base.text_of_utf8 "for"

let s_218 = Base.text_of_utf8 "invalid loop pattern"

let s_219 = Base.text_of_utf8 "unknown_operator"

let s_220 = Base.text_of_utf8 "operator has no source fixity declaration: "

let s_221 = Base.text_of_utf8 "named_operator"

let s_222 = Base.text_of_utf8 "expression_complexity"

let s_223 = Base.text_of_utf8 "loop binding analysis exceeded its source-tree bound"

let s_224 = Base.text_of_utf8 "body"

let s_225 = Base.text_of_utf8 "type_argument"

let s_226 = Base.text_of_utf8 "effect application exceeds the source-tree limit"

let s_227 = Base.text_of_utf8 "annotation scope exceeds the source-tree limit"

let s_228 = Base.text_of_utf8 "annotation_kind_mismatch"

let s_229 = Base.text_of_utf8 "one annotation name cannot be both a type and an effect-row variable"

let s_230 = Base.text_of_utf8 "source tree exhausted its node-count bound"

let s_231 = Base.text_of_utf8 "$record$"

let s_232 = Base.text_of_utf8 "index"

let s_233 = Base.text_of_utf8 "call_arity"

let s_234 = Base.text_of_utf8 "@type.call requires a literal member name and two operands"

let s_235 = Base.text_of_utf8 " requires "

let s_236 = Base.text_of_utf8 " arguments"

let s_237 = Base.text_of_utf8 "scalar intrinsics require exactly two arguments"

let s_238 = Base.text_of_utf8 "unary intrinsics require exactly one argument"

let s_239 = Base.text_of_utf8 "@panic requires exactly one literal message"

let s_240 = Base.text_of_utf8 "wrong number of arguments to compiler primitive "

let s_241 = Base.text_of_utf8 "argument"

let s_242 = Base.text_of_utf8 "parameter"

let s_243 = Base.text_of_utf8 "values"

let s_244 = Base.text_of_utf8 "arms"

let s_245 = Base.text_of_utf8 "patterns"

let s_246 = Base.text_of_utf8 "resolver"

let s_247 = Base.text_of_utf8 "invalid do resolver field"

let s_248 = Base.text_of_utf8 "unsupported_expression"

let s_249 = Base.text_of_utf8 "expression is not implemented in the executable core"

let s_250 = Base.text_of_utf8 "fallback"

let s_251 = Base.text_of_utf8 "$let$"

let s_252 = Base.text_of_utf8 "state"

let s_253 = Base.text_of_utf8 "next$"

let s_254 = Base.text_of_utf8 "$for$"

let s_255 = Base.text_of_utf8 "end"

let s_256 = Base.text_of_utf8 "start"

let s_257 = Base.text_of_utf8 "invalid range endpoint"

let s_258 = Base.text_of_utf8 "path"

let s_259 = Base.text_of_utf8 "$update$self$"

let s_260 = Base.text_of_utf8 "$update$parent$"

let s_261 = Base.text_of_utf8 "$update$index$"

let s_262 = Base.text_of_utf8 "unknown update selector"

let s_263 = Base.text_of_utf8 "forwarding"

let s_264 = Base.text_of_utf8 "consequence"

let s_265 = Base.text_of_utf8 "condition"

let s_266 = Base.text_of_utf8 "$if$"

let s_267 = Base.text_of_utf8 "duplicate_name"

let s_268 = Base.text_of_utf8 "duplicate value or constructor declaration"

let s_269 = Base.text_of_utf8 "duplicate_type"

let s_270 = Base.text_of_utf8 "duplicate type declaration"

let s_271 = Base.text_of_utf8 "type_record"

let s_272 = Base.text_of_utf8 "Foreign is reserved for the compiler's host-call effect label"

let s_273 = Base.text_of_utf8 "operations"

let s_274 = Base.text_of_utf8 "value initializer exceeds the source-tree limit"

let s_275 = Base.text_of_utf8 "constructors"

let s_276 = Base.text_of_utf8 "attributes"

let s_277 = Base.text_of_utf8 "operator_header_order"

let s_278 = Base.text_of_utf8 "operator declarations must precede values and data declarations"

let s_279 = Base.text_of_utf8 "symbol"

let s_280 = Base.text_of_utf8 "target"

let s_281 = Base.text_of_utf8 "operator_precedence"

let s_282 = Base.text_of_utf8 "operator precedence must be between 0 and 255"

let s_283 = Base.text_of_utf8 "duplicate_operator"

let s_284 = Base.text_of_utf8 "duplicate operator fixity declaration"

let s_285 = Base.text_of_utf8 "associativity"

let s_286 = Base.text_of_utf8 "precedence"

let s_287 = Base.text_of_utf8 "recursive_tag"

let s_288 = Base.text_of_utf8 "a tagged declaration cannot refer to its own bound name"

let s_289 = Base.text_of_utf8 "let"

let s_290 = Base.text_of_utf8 "duplicate_type_parameter"

let s_291 = Base.text_of_utf8 "duplicate type parameter"

let s_292 = Base.text_of_utf8 "invalid constructor record fields"

let s_293 = Base.text_of_utf8 "operation_signature"

let s_294 = Base.text_of_utf8 "an operation declaration specifies parameter and result types, not an outer latent effect row"

let s_295 = Base.text_of_utf8 "an effect operation requires a unary signature: Parameter -> Result"

let s_296 = Base.text_of_utf8 "signature"

let s_297 = Base.text_of_utf8 "empty_effect"

let s_298 = Base.text_of_utf8 "an effect group requires at least one operation"

let s_299 = Base.text_of_utf8 "parameters"

let s_300 = Base.text_of_utf8 "unknown_modifier"

let s_301 = Base.text_of_utf8 "only `entry` may precede `const` or `let`"

let s_302 = Base.text_of_utf8 "entry_outside_entry_module"

let s_303 = Base.text_of_utf8 "`entry` marks a host entrypoint and is only allowed in the entry module; other modules' declarations stay importable without it"

let s_304 = Base.text_of_utf8 "entry"

let s_305 = Base.text_of_utf8 "a declaration has at most one modifier"

let s_306 = Base.text_of_utf8 "unsupported_attribute"

let s_307 = Base.text_of_utf8 "expression tags apply only to const and let declarations"

let s_308 = Base.text_of_utf8 "modifier"

let s_309 = Base.text_of_utf8 "labels"

let s_310 = Base.text_of_utf8 "effect-row source tree exhausted its node-count bound"

let s_311 = Base.text_of_utf8 "effect_row"

let s_312 = Base.text_of_utf8 "$prelude."

let s_313 = Base.text_of_utf8 "std/prelude"

let s_314 = Base.text_of_utf8 "declarations"

let s_315 = Base.text_of_utf8 "module_loader_required"

let s_316 = Base.text_of_utf8 "compile a source project to resolve file imports"

let s_317 = Base.text_of_utf8 "main"

let s_318 = Base.text_of_utf8 "imports"

let rec (* lower.bend:151 *)
f_classify_initial : Base.char32 -> Base.text -> t_NodeKind =
fun v_initial v_kind ->
(match v_initial with
| (Chr (Base.W32 0x49)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_0))) (Integer) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_1))) (Intrinsic) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_2))) (PatternName) (Unsupported))))))
| (Chr (Base.W32 0x46)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_3))) (Float) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_4))) (Falsehood) (Unsupported))))
| (Chr (Base.W32 0x54)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_5))) (Truth) (Unsupported))
| (Chr (Base.W32 0x61)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_6))) (Wrapper) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_7))) (ArrayNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_8))) (ApplicationNode) (Unsupported))))))
| (Chr (Base.W32 0x62)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_9))) (Binding) (Unsupported))
| (Chr (Base.W32 0x63)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_10))) (ApplicationNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_11))) (CaseNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_12))) (Conditional) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_13))) (PatternConstructor) (Unsupported))))))))
| (Chr (Base.W32 0x64)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_14))) (DataNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_15))) (Block) (Unsupported))))
| (Chr (Base.W32 0x65)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_16))) (ForLoop) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_17))) (Wrapper) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_18))) (EffectBinding) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_19))) (EffectBinding) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_20))) (EffectNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_21))) (EffectTypeNode) (Unsupported))))))))))))
| (Chr (Base.W32 0x66)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_22))) (ForLoop) (Unsupported))
| (Chr (Base.W32 0x67)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_23))) (GroupNode) (Unsupported))
| (Chr (Base.W32 0x69)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_24))) (InfixNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_25))) (IndexNode) (Unsupported))))
| (Chr (Base.W32 0x6c)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_26))) (LambdaNode) (Unsupported))
| (Chr (Base.W32 0x6d)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_27))) (MemberNode) (Unsupported))
| (Chr (Base.W32 0x6e)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_28))) (NamedFixity) (Unsupported))
| (Chr (Base.W32 0x70)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_29))) (PrefixNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_30))) (PatternConditional) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_31))) (PatternWrapper) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_32))) (PatternGroup) (Unsupported))))))))
| (Chr (Base.W32 0x76)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_33))) (PatternValue) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_34))) (ValueDeclaration) (Unsupported))))
| (Chr (Base.W32 0x71)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_35))) (Name) (Unsupported))
| (Chr (Base.W32 0x72)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_36))) (ForLoop) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_37))) (RecordNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_38))) (Return) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_39))) (Rebinding) (Unsupported))))))))
| (Chr (Base.W32 0x73)) ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_40))) (SymbolicFixity) (Unsupported))
| _ ->
Unsupported)
and (* lower.bend:194 *)
f_classify : Base.text -> t_NodeKind =
fun v_kind ->
(match v_kind with
| SNil ->
Unsupported
| (SCon (v_initial, v_tail)) ->
(f_classify_initial (v_initial) (v_kind)))
and (* lower.bend:201 *)
f_visit : C.t_Cst -> t_Work =
fun v_node ->
(Expression ((f_classify ((C.f_kind_of (v_node)))), v_node))
and (* lower.bend:204 *)
f_lookup_local_work : (t_Local) list -> Base.text -> (Base.text) option -> (Base.text) option =
fun v_locals v_name v_found ->
(match (v_locals, v_found) with
| (_, (Some (v_core))) ->
(Some (v_core))
| ([], None) ->
None
| (((Local (v_source, v_core)) :: v_tail), None) ->
(f_lookup_local_work (v_tail) (v_name) ((Base.bool_pick ((M.f_name_equal (v_source) (v_name))) ((Some (v_core))) (None)))))
and (* lower.bend:213 *)
f_lookup_local : (t_Local) list -> Base.text -> (Base.text) option =
fun v_locals v_name ->
(f_lookup_local_work (v_locals) (v_name) (None))
and (* lower.bend:216 *)
f_lookup_global : (t_Global) Base.map -> Base.text -> (t_Global) option =
fun v_globals v_name ->
(Index.f_find (v_globals) (v_name))
and (* lower.bend:221 *)
f_instantiate_at : int -> int -> M.t_Expr -> M.t_Expr =
fun v_offset v_lane v_value ->
(M.InstantiationExpr ((Base.nat_add ((Base.nat_mul (v_offset) (16))) (v_lane)), v_value))
and (* lower.bend:224 *)
f_global_value : (t_Global) option -> C.t_Cst -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_found v_node ->
(match v_found with
| (Some ((Global (v_source, v_core, ConstantName)))) ->
(Done ((f_instantiate_at ((C.f_offset_of (v_node))) (0) ((M.ConstantExpr (v_core))))))
| (Some ((Global (v_source, v_core, FunctionName)))) ->
(Done ((f_instantiate_at ((C.f_offset_of (v_node))) (0) ((M.FunctionExpr (v_core))))))
| (Some ((Global (v_source, v_core, ConstructorName)))) ->
(Done ((f_instantiate_at ((C.f_offset_of (v_node))) (0) ((M.ConstructorRefExpr (v_core))))))
| (Some ((Global (v_source, v_core, (RecordConstructorName (v_fields)))))) ->
(Done ((f_instantiate_at ((C.f_offset_of (v_node))) (0) ((M.ConstructorRefExpr (v_core))))))
| (Some ((Global (v_source, v_core, (OperationName (v_identity)))))) ->
(Done ((M.OperationExpr (v_identity))))
| (Some ((Global (v_source, v_core, (OperationTemplateName (v_identity, v_parameters)))))) ->
(Done ((M.GenericOperationExpr ((C.f_offset_of (v_node)), v_identity, []))))
| (Some ((Global (v_source, v_core, (EffectFamilyName (v_members, v_parameters)))))) ->
(Fail ((C.f_diagnostic (v_node) (s_41) (s_42))))
| None ->
(Fail ((C.f_diagnostic (v_node) (s_43) ((Base.string_append s_44 (C.f_name_of (v_node))))))))
and (* lower.bend:243 *)
f_located : int -> M.t_Expr -> M.t_Expr =
fun v_offset v_value ->
(M.SourceExpr (v_offset, None, v_value))
and (* lower.bend:246 *)
f_member_path : (C.t_Cst) list -> M.t_Expr -> M.t_Expr =
fun v_nodes v_receiver ->
(match v_nodes with
| [] ->
v_receiver
| ((C.Cst (v_kind, v_field, (SCon (Chr (Base.W32 0x2e), SNil)), v_offset, v_children)) :: v_tail) ->
(f_member_path (v_tail) (v_receiver))
| ((C.Cst (v_kind, v_field, v_member, v_offset, v_children)) :: v_tail) ->
(f_member_path (v_tail) ((f_located (v_offset) ((f_instantiate_at (v_offset) (2) ((M.AssociatedExpr (v_offset, M.MemberDispatch, v_member, [], v_receiver, M.UnitExpr)))))))))
and (* lower.bend:258 *)
f_prefix_candidate : (t_Global) option -> (C.t_Cst) list -> (t_GlobalPrefix) option -> (t_GlobalPrefix) option =
fun v_found v_tail v_previous ->
(match v_found with
| (Some (v_global)) ->
(Some ((GlobalPrefix (v_global, v_tail))))
| None ->
v_previous)
and (* lower.bend:265 *)
f_global_prefix : (C.t_Cst) list -> (t_Global) Base.map -> Base.text -> (t_GlobalPrefix) option -> (t_GlobalPrefix) option =
fun v_nodes v_globals v_prefix v_best ->
(match v_nodes with
| [] ->
v_best
| ((C.Cst (v_kind, v_field, (SCon (Chr (Base.W32 0x2e), SNil)), v_offset, v_children)) :: v_tail) ->
(f_global_prefix (v_tail) (v_globals) ((Base.string_append v_prefix s_45)) (v_best))
| ((C.Cst (v_kind, v_field, v_text, v_offset, v_children)) :: v_tail) ->
(let v_name = (Base.string_append v_prefix v_text) in
(f_global_prefix (v_tail) (v_globals) (v_name) ((f_prefix_candidate ((f_lookup_global (v_globals) (v_name))) (v_tail) (v_best))))))
and (* lower.bend:275 *)
f_global_member : (t_GlobalPrefix) option -> C.t_Cst -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_found v_node ->
(match v_found with
| (Some ((GlobalPrefix (v_global, v_remaining)))) ->
(match (f_global_value ((Some (v_global))) (v_node)) with
| Fail __error -> Fail __error
| Done v_receiver ->
(Done ((f_member_path (v_remaining) (v_receiver)))))
| None ->
(f_global_value (None) (v_node)))
and (* lower.bend:284 *)
f_resolve_root : (Base.text) option -> C.t_Cst -> (C.t_Cst) list -> (t_Global) Base.map -> C.t_Cst -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_found v_root v_nodes v_globals v_node ->
(match v_found with
| (Some (v_core)) ->
(Done ((f_member_path (v_nodes) ((f_instantiate_at ((C.f_offset_of (v_root))) (0) ((M.LocalExpr (v_core))))))))
| None ->
(f_global_member ((f_global_prefix ((C.f_children_of (v_node))) (v_globals) (s_46) (None))) (v_node)))
and (* lower.bend:291 *)
f_resolve_parts : (C.t_Cst) list -> t_Context -> C.t_Cst -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_nodes v_context v_node ->
(match (v_nodes, v_context) with
| ((v_root :: v_tail), (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_variables))) ->
(f_resolve_root ((f_lookup_local (v_locals) ((C.f_text_of (v_root))))) (v_root) (v_tail) (v_globals) (v_node))
| (_, _) ->
(Fail ((C.f_diagnostic (v_node) (s_47) (s_48)))))
and (* lower.bend:298 *)
f_resolve : t_Context -> C.t_Cst -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_context v_node ->
(f_resolve_parts ((C.f_children_of (v_node))) (v_context) (v_node))
and (* lower.bend:301 *)
f_template_reference : (Base.text) option -> (t_Global) option -> (t_TemplateReference) option =
fun v_local v_found ->
(match (v_local, v_found) with
| (None, (Some ((Global (v_source, v_core, (OperationTemplateName (v_identity, v_parameters))))))) ->
(Some ((TemplateReference (v_identity, v_parameters))))
| (_, _) ->
None)
and (* lower.bend:308 *)
f_effect_template_found : (t_Global) option -> C.t_Cst -> (M.t_Diagnostic, M.t_TypeId) Base.result_ =
fun v_found v_node ->
(match v_found with
| (Some ((Global (v_source, v_core, (OperationTemplateName (v_identity, ((A.Binding (v_parameter)) :: []))))))) ->
(Done (v_identity))
| (Some ((Global (v_source, v_core, (OperationTemplateName (v_identity, v_parameters)))))) ->
(Fail ((C.f_diagnostic (v_node) (s_49) (s_50))))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_51) (s_52)))))
and (* lower.bend:317 *)
f_effect_template_child : (C.t_Cst) list -> C.t_Cst -> t_Context -> (M.t_Diagnostic, M.t_TypeId) Base.result_ =
fun v_children v_node v_context ->
(match v_children with
| (v_name :: []) ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(Base.bool_pick ((M.f_name_equal ((C.f_kind_of (v_name))) (s_35))) ((f_effect_template_found ((f_lookup_global (v_globals) ((C.f_name_of (v_name))))) (v_node))) ((Fail ((C.f_diagnostic (v_node) (s_51) (s_53)))))))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_51) (s_53)))))
and (* lower.bend:325 *)
f_effect_template_name : C.t_Cst -> t_Context -> (M.t_Diagnostic, M.t_TypeId) Base.result_ =
fun v_node v_context ->
(f_effect_template_child ((C.f_children_of (v_node))) (v_node) (v_context))
and (* lower.bend:328 *)
f_family_contains : (M.t_TypeId) list -> M.t_TypeId -> bool =
fun v_members v_wanted ->
(match v_members with
| [] ->
false
| (v_member :: v_rest) ->
(Base.bool_or ((M.f_type_id_equal (v_member) (v_wanted))) ((f_family_contains (v_rest) (v_wanted)))))
and (* lower.bend:335 *)
f_family_pair : (t_Global) list -> M.t_TypeId -> M.t_TypeId -> bool =
fun v_globals v_reader v_writer ->
(match v_globals with
| [] ->
false
| ((Global (v_source, v_core, (EffectFamilyName (v_members, v_parameters)))) :: v_rest) ->
(Base.bool_or ((Base.bool_and ((f_family_contains (v_members) (v_reader))) ((f_family_contains (v_members) (v_writer))))) ((f_family_pair (v_rest) (v_reader) (v_writer))))
| (v_other :: v_rest) ->
(f_family_pair (v_rest) (v_reader) (v_writer)))
and (* lower.bend:344 *)
f_require_family_pair : t_Context -> M.t_TypeId -> M.t_TypeId -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_context v_reader v_writer v_node ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(Base.bool_pick ((f_family_pair ((Base.map_values (v_globals))) (v_reader) (v_writer))) ((Done (()))) ((Fail ((C.f_diagnostic (v_node) (s_54) (s_55)))))))
and (* lower.bend:348 *)
f_effect_member_instances : (M.t_TypeId) list -> (M.t_Ty) list -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_ =
fun v_templates v_arguments ->
(match v_templates with
| [] ->
(Done ([]))
| (v_template :: v_rest) ->
(match (Families.f_identity (v_template) (v_arguments)) with
| Fail __error -> Fail __error
| Done v_identity ->
(match (f_effect_member_instances (v_rest) (v_arguments)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((v_identity :: v_following))))))
and (* lower.bend:358 *)
f_lookup_effect_resolved : bool -> (t_Global) option -> Base.text -> (A.t_Value) list -> C.t_Cst -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_ =
fun v_sealed v_found v_name v_values v_node ->
(match (v_sealed, v_found) with
| (true, _) ->
(match (A.f_bind ([]) (v_values) (v_node)) with
| Fail __error -> Fail __error
| Done v_arguments ->
(Done ([(M.f_foreign_identity ())])))
| (false, (Some ((Global (v_source, v_core, (OperationName (v_identity))))))) ->
(match (A.f_bind ([]) (v_values) (v_node)) with
| Fail __error -> Fail __error
| Done v_arguments ->
(Done ([v_identity])))
| (false, (Some ((Global (v_source, v_core, (OperationTemplateName (v_identity, v_parameters))))))) ->
(match (A.f_bind (v_parameters) (v_values) (v_node)) with
| Fail __error -> Fail __error
| Done v_arguments ->
(match (Families.f_identity (v_identity) (v_arguments)) with
| Fail __error -> Fail __error
| Done v_concrete ->
(Done ([v_concrete]))))
| (false, (Some ((Global (v_source, v_core, (EffectFamilyName (v_members, v_parameters))))))) ->
(match (A.f_bind (v_parameters) (v_values) (v_node)) with
| Fail __error -> Fail __error
| Done v_arguments ->
(f_effect_member_instances (v_members) (v_arguments)))
| (_, _) ->
(Fail ((M.Diagnostic (s_56, v_name, s_57)))))
and (* lower.bend:380 *)
f_lookup_effect : (t_Global) Base.map -> Base.text -> (A.t_Value) list -> C.t_Cst -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_ =
fun v_globals v_name v_arguments v_node ->
(let v_lookup_name = v_name in
(f_lookup_effect_resolved ((M.f_name_equal (v_lookup_name) (s_58))) ((f_lookup_global (v_globals) (v_lookup_name))) (v_lookup_name) (v_arguments) (v_node)))
and (* lower.bend:384 *)
f_type_value : int -> C.t_Cst -> t_Context -> (M.t_Diagnostic, A.t_Value) Base.result_ =
fun v_fuel v_node v_context ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(match (T.f_evaluate (f_lookup_effect) (v_fuel) ((T.f_visit (v_node))) (v_headers) (v_annotation_variables) (v_globals)) with
| Fail __error -> Fail __error
| Done v_values ->
(T.f_one_value (v_values))))
and (* lower.bend:390 *)
f_type_term : int -> C.t_Cst -> t_Context -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_fuel v_node v_context ->
(match (f_type_value (v_fuel) (v_node) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(A.f_as_type (v_value) (v_node)))
and (* lower.bend:395 *)
f_typed_arguments : (A.t_Pattern) list -> (C.t_Cst) list -> int -> t_Context -> (M.t_Ty) list -> C.t_Cst -> (M.t_Diagnostic, t_TypedArguments) Base.result_ =
fun v_parameters v_nodes v_fuel v_context v_reversed v_head ->
(match (v_parameters, v_nodes) with
| ([], v_rest) ->
(Done ((TypedArguments ((Base.list_reverse (v_reversed)), v_rest))))
| ((v_pattern :: v_remaining), []) ->
(Fail ((C.f_diagnostic (v_head) (s_49) (s_59))))
| ((v_pattern :: v_remaining), (v_node :: v_rest)) ->
(match (f_type_value (v_fuel) (v_node) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (A.f_match_argument (v_fuel) ((A.Argument (v_pattern, v_value))) (v_node)) with
| Fail __error -> Fail __error
| Done v_types ->
(f_typed_arguments (v_remaining) (v_rest) (v_fuel) (v_context) ((Base.list_reverse_go (v_types) (v_reversed))) (v_head)))))
and (* lower.bend:407 *)
f_typed_operation : t_TemplateReference -> (C.t_Cst) list -> int -> t_Context -> C.t_Cst -> (M.t_Diagnostic, t_TypedArguments) Base.result_ =
fun v_template v_nodes v_fuel v_context v_head ->
(let (TemplateReference (v_identity, v_parameters)) = v_template in
(f_typed_arguments (v_parameters) (v_nodes) (v_fuel) (v_context) ([]) (v_head)))
and (* lower.bend:411 *)
f_builtin_type_name : Base.text -> bool =
fun v_name ->
(Base.bool_or ((M.f_name_equal (v_name) (s_60))) ((Base.bool_or ((M.f_name_equal (v_name) (s_61))) ((Base.bool_or ((M.f_name_equal (v_name) (s_62))) ((Base.bool_or ((M.f_name_equal (v_name) (s_63))) ((M.f_name_equal (v_name) (s_64))))))))))
and (* lower.bend:414 *)
f_extra_type_argument_child : (C.t_Cst) list -> t_Context -> bool =
fun v_children v_context ->
(match v_children with
| (v_name :: []) ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(let v_source = (C.f_type_name (v_name)) in
(Base.bool_and ((M.f_name_equal ((C.f_kind_of (v_name))) (s_35))) ((Base.bool_and ((Base.bool_or ((f_builtin_type_name (v_source))) ((Base.maybe_is_some ((T.f_lookup_header (v_headers) (v_source))))))) ((Base.bool_not ((Base.maybe_is_some ((f_lookup_global (v_globals) (v_source))))))))))))
| _ ->
false)
and (* lower.bend:423 *)
f_extra_type_argument : (C.t_Cst) list -> t_Context -> bool =
fun v_nodes v_context ->
(match v_nodes with
| [] ->
false
| (v_node :: v_tail) ->
(f_extra_type_argument_child ((C.f_children_of (v_node))) (v_context)))
and (* lower.bend:430 *)
f_local_operation_argument : int -> T.t_Work -> t_Context -> bool =
fun v_fuel v_work v_context ->
(match (v_fuel, v_work) with
| (__nat_1, (T.Node (T.Name, v_node))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(Base.maybe_is_some ((f_lookup_local (v_locals) ((C.f_type_name (v_node))))))))
| (__nat_2, (T.Node (T.Wrapper, v_node))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_local_operation_argument (v_rest) ((T.Nodes ((C.f_children_of (v_node))))) (v_context)))
| (__nat_3, (T.Node (T.Group, v_node))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_local_operation_argument (v_rest) ((T.Nodes ((C.f_field_values (v_node) (s_65))))) (v_context)))
| (__nat_4, (T.Node (T.Application, v_node))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_local_operation_argument (v_rest) ((T.Nodes ((Base.list_append ((C.f_field_values (v_node) (s_66))) ((C.f_field_values (v_node) (s_67))))))) (v_context)))
| (__nat_5, (T.Node (T.ArrayNode, v_node))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_local_operation_argument (v_rest) ((T.Nodes ((C.f_field_values (v_node) (s_68))))) (v_context)))
| (__nat_6, (T.Node (T.RecordNode, v_node))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_local_operation_argument (v_rest) ((T.Nodes ((C.f_field_values (v_node) (s_69))))) (v_context)))
| (__nat_7, (T.Node (T.FieldNode, v_node))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_local_operation_argument (v_rest) ((T.Field (v_node, (C.f_field_values (v_node) (s_65))))) (v_context)))
| (__nat_8, (T.Field (v_node, []))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_local_operation_argument (v_rest) ((T.Nodes ((C.f_field_values (v_node) (s_70))))) (v_context)))
| (__nat_9, (T.Field (v_node, v_values))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_local_operation_argument (v_rest) ((T.Nodes (v_values))) (v_context)))
| (__nat_10, (T.Node (T.InfixNode, v_node))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(Base.bool_and ((Base.list_is_empty ((C.f_field_values (v_node) (s_71))))) ((f_local_operation_argument (v_rest) ((T.Nodes ((C.f_field_values (v_node) (s_66))))) (v_context)))))
| (__nat_11, (T.Node (T.PrefixNode, v_node))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(Base.bool_and ((Base.list_is_empty ((C.f_field_values (v_node) (s_72))))) ((f_local_operation_argument (v_rest) ((T.Nodes ((C.f_field_values (v_node) (s_65))))) (v_context)))))
| (__nat_12, (T.Nodes ((v_node :: v_tail)))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(Base.bool_or ((f_local_operation_argument (v_rest) ((T.f_visit (v_node))) (v_context))) ((f_local_operation_argument (v_rest) ((T.Nodes (v_tail))) (v_context)))))
| (_, _) ->
false)
and (* lower.bend:460 *)
f_operation_argument_matches : (M.t_Diagnostic, (M.t_Ty) list) Base.result_ -> bool =
fun v_matched ->
(match v_matched with
| (Done (v_types)) ->
true
| (Fail (v_diagnostic)) ->
false)
and (* lower.bend:467 *)
f_operation_value_is_explicit : (M.t_Diagnostic, A.t_Value) Base.result_ -> bool -> (A.t_Pattern) list -> int -> C.t_Cst -> bool =
fun v_value v_has_runtime_argument v_parameters v_fuel v_node ->
(match (v_value, v_parameters) with
| ((Done ((A.TupleValue ([])))), _) ->
v_has_runtime_argument
| ((Done (v_value)), (v_pattern :: v_tail)) ->
(f_operation_argument_matches ((A.f_match_argument (v_fuel) ((A.Argument (v_pattern, v_value))) (v_node))))
| (_, _) ->
false)
and (* lower.bend:476 *)
f_empty_operation_pattern : (A.t_Pattern) list -> bool =
fun v_parameters ->
(match v_parameters with
| ((A.TuplePattern ([])) :: v_tail) ->
true
| _ ->
false)
and (* lower.bend:483 *)
f_operation_arguments_explicit : (C.t_Cst) list -> (A.t_Pattern) list -> int -> t_Context -> bool =
fun v_arguments v_parameters v_fuel v_context ->
(match v_arguments with
| [] ->
false
| (v_head :: v_tail) ->
(let v_has_runtime_argument = (Base.nat_is_ge ((Base.list_length (v_tail))) ((Base.list_length (v_parameters)))) in
(Base.bool_and ((Base.bool_or (v_has_runtime_argument) ((Base.bool_not ((f_local_operation_argument (v_fuel) ((T.f_visit (v_head))) (v_context))))))) ((f_operation_value_is_explicit ((f_type_value (v_fuel) (v_head) (v_context))) ((Base.bool_or ((f_empty_operation_pattern (v_parameters))) (v_has_runtime_argument))) (v_parameters) (v_fuel) (v_head))))))
and (* lower.bend:491 *)
f_specialized_operation_named : bool -> M.t_TypeId -> (M.t_Ty) list -> C.t_Cst -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_concrete v_identity v_arguments v_head ->
(match v_concrete with
| false ->
(Done ((M.GenericOperationExpr ((C.f_offset_of (v_head)), v_identity, v_arguments))))
| true ->
(match (Families.f_identity (v_identity) (v_arguments)) with
| Fail __error -> Fail __error
| Done v_concrete ->
(Done ((M.SpecializeOperationExpr (v_identity, v_arguments, (M.OperationExpr (v_concrete))))))))
and (* lower.bend:500 *)
f_specialized_operation_value : M.t_TypeId -> (M.t_Ty) list -> C.t_Cst -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_identity v_arguments v_head ->
(match (CoreTypes.f_annotation_names (65536) ((CoreTypes.ManyTypes (v_arguments)))) with
| Fail __error -> Fail __error
| Done v_names ->
(f_specialized_operation_named ((Base.list_is_empty (v_names))) (v_identity) (v_arguments) (v_head)))
and (* lower.bend:505 *)
f_typed_operation_parsed : t_TypedArguments -> M.t_TypeId -> t_Context -> C.t_Cst -> (M.t_Diagnostic, t_TypedCall) Base.result_ =
fun v_parsed v_identity v_context v_head ->
(match v_parsed with
| (TypedArguments (v_types, v_values)) ->
(match (Base.bool_pick ((f_extra_type_argument (v_values) (v_context))) ((Fail ((C.f_diagnostic (v_head) (s_49) (s_73))))) ((Done (())))) with
| Fail __error -> Fail __error
| Done v_extra ->
(match (f_specialized_operation_value (v_identity) (v_types) (v_head)) with
| Fail __error -> Fail __error
| Done v_callee ->
(Done ((TypedCall (v_callee, v_values)))))))
and (* lower.bend:513 *)
f_operation_application : bool -> t_TemplateReference -> (C.t_Cst) list -> int -> t_Context -> C.t_Cst -> (M.t_Diagnostic, t_TypedCall) Base.result_ =
fun v_explicit v_template v_arguments v_fuel v_context v_head ->
(match v_explicit with
| false ->
(let (TemplateReference (v_identity, v_parameters)) = v_template in
(Done ((TypedCall ((M.GenericOperationExpr ((C.f_offset_of (v_head)), v_identity, [])), v_arguments)))))
| true ->
(let (TemplateReference (v_identity, v_parameters)) = v_template in
(match (f_typed_operation (v_template) (v_arguments) (v_fuel) (v_context) (v_head)) with
| Fail __error -> Fail __error
| Done v_parsed ->
(f_typed_operation_parsed (v_parsed) (v_identity) (v_context) (v_head)))))
and (* lower.bend:524 *)
f_typed_operation_value : t_TemplateReference -> (C.t_Cst) list -> int -> t_Context -> C.t_Cst -> (M.t_Diagnostic, t_TypedCall) Base.result_ =
fun v_template v_arguments v_fuel v_context v_head ->
(let (TemplateReference (v_identity, v_parameters)) = v_template in
(f_operation_application ((f_operation_arguments_explicit (v_arguments) (v_parameters) (v_fuel) (v_context))) (v_template) (v_arguments) (v_fuel) (v_context) (v_head)))
and (* lower.bend:528 *)
f_typed_call_work : t_TypedCall -> int -> t_Work =
fun v_typed v_offset ->
(let (TypedCall (v_callee, v_values)) = v_typed in
(Arguments (v_callee, v_values, v_offset)))
and (* lower.bend:532 *)
f_record_name : C.t_Cst -> Base.text =
fun v_node ->
(match v_node with
| (C.Cst (v_kind, v_field, v_text, v_offset, [])) ->
v_text
| (C.Cst (v_kind, v_field, v_text, v_offset, v_children)) ->
(C.f_texts (v_children)))
and (* lower.bend:539 *)
f_record_global : (Base.text) option -> (t_Global) option -> C.t_Cst -> (M.t_Diagnostic, t_RecordTarget) Base.result_ =
fun v_local v_found v_node ->
(match (v_local, v_found) with
| (None, (Some ((Global (v_source, v_core, (RecordConstructorName (v_fields))))))) ->
(Done ((RecordTarget (v_core, v_fields))))
| (None, None) ->
(Fail ((C.f_diagnostic (v_node) (s_74) ((Base.string_append s_75 (f_record_name (v_node)))))))
| (_, _) ->
(Fail ((C.f_diagnostic (v_node) (s_76) (s_77)))))
and (* lower.bend:548 *)
f_record_target : t_Context -> C.t_Cst -> (M.t_Diagnostic, t_RecordTarget) Base.result_ =
fun v_context v_node ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(let v_name = (f_record_name (v_node)) in
(f_record_global ((f_lookup_local (v_locals) (v_name))) ((f_lookup_global (v_globals) (v_name))) (v_node))))
and (* lower.bend:553 *)
f_record_field_present : (Base.text) list -> Base.text -> bool =
fun v_fields v_name ->
(match v_fields with
| [] ->
false
| (v_head :: v_tail) ->
(Base.bool_or ((M.f_name_equal (v_head) (v_name))) ((f_record_field_present (v_tail) (v_name)))))
and (* lower.bend:560 *)
f_record_field_valid : bool -> bool -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_known v_duplicate v_node ->
(match (v_known, v_duplicate) with
| (false, _) ->
(Fail ((C.f_diagnostic (v_node) (s_78) ((Base.string_append s_79 (C.f_text_of (v_node)))))))
| (true, true) ->
(Fail ((C.f_diagnostic (v_node) (s_80) ((Base.string_append s_81 (C.f_text_of (v_node)))))))
| (true, false) ->
(Done (())))
and (* lower.bend:569 *)
f_record_field_names : (C.t_Cst) list -> Base.set -> (Base.text) list -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_nodes v_seen v_reversed ->
(match v_nodes with
| [] ->
(Done ((Base.list_reverse (v_reversed))))
| (v_node :: v_rest) ->
(match (C.f_one ((C.f_field_values (v_node) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name_node ->
(match (Done ((C.f_text_of (v_name_node)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_record_field_valid (true) ((Base.maybe_is_some ((Index.f_find (v_seen) (v_name))))) (v_name_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_record_field_names (v_rest) ((Base.set_add (v_seen) (v_name))) ((v_name :: v_reversed)))))))
and (* lower.bend:580 *)
f_record_kind : (C.t_Cst) list -> (M.t_Diagnostic, t_GlobalKind) Base.result_ =
fun v_nodes ->
(match v_nodes with
| [] ->
(Done (ConstructorName))
| (v_node :: []) ->
(match (f_record_field_names ((C.f_field_values (v_node) (s_69))) (MTip) ([])) with
| Fail __error -> Fail __error
| Done v_fields ->
(Done ((RecordConstructorName (v_fields)))))
| _ ->
(Fail ((M.Diagnostic (s_47, s_82, s_83)))))
and (* lower.bend:591 *)
f_record_value_node : (C.t_Cst) list -> C.t_Cst -> (M.t_Diagnostic, C.t_Cst) Base.result_ =
fun v_values v_name ->
(match v_values with
| [] ->
(Done ((C.Cst (s_35, s_65, s_46, (C.f_offset_of (v_name)), [v_name]))))
| (v_value :: []) ->
(Done (v_value))
| _ ->
(Fail ((C.f_diagnostic (v_name) (s_47) (s_84)))))
and (* lower.bend:600 *)
f_record_element_binding : (t_RecordElement) list -> Base.text -> (Base.text) option =
fun v_elements v_field ->
(match v_elements with
| [] ->
None
| ((RecordElement (v_label, v_binding, v_value)) :: v_rest) ->
(Base.bool_pick ((M.f_name_equal (v_field) (v_label))) ((Some (v_binding))) ((f_record_element_binding (v_rest) (v_field)))))
and (* lower.bend:607 *)
f_require_record_element : (Base.text) option -> Base.text -> C.t_Cst -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_found v_field v_node ->
(match v_found with
| (Some (v_binding)) ->
(Done ((M.LocalExpr (v_binding))))
| None ->
(Fail ((C.f_diagnostic (v_node) (s_85) ((Base.string_append s_86 v_field))))))
and (* lower.bend:614 *)
f_record_payload_elements : (Base.text) list -> (t_RecordElement) list -> C.t_Cst -> (M.t_Expr) list -> (M.t_Diagnostic, (M.t_Expr) list) Base.result_ =
fun v_fields v_elements v_node v_reversed ->
(match v_fields with
| [] ->
(Done ((Base.list_reverse (v_reversed))))
| (v_field :: v_rest) ->
(match (f_require_record_element ((f_record_element_binding (v_elements) (v_field))) (v_field) (v_node)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_record_payload_elements (v_rest) (v_elements) (v_node) ((v_value :: v_reversed)))))
and (* lower.bend:623 *)
f_record_payload : (M.t_Expr) list -> (M.t_Expr) option =
fun v_values ->
(match v_values with
| [] ->
None
| (v_value :: []) ->
(Some (v_value))
| (v_first :: (v_second :: v_rest)) ->
(Some ((M.ProductExpr ((v_first :: (v_second :: v_rest)))))))
and (* lower.bend:633 *)
f_record_bindings : (t_RecordElement) list -> M.t_Expr -> M.t_Expr =
fun v_reversed v_body ->
(match v_reversed with
| [] ->
v_body
| ((RecordElement (v_field, v_binding, v_value)) :: v_rest) ->
(f_record_bindings (v_rest) ((M.UseExpr (v_binding, v_value, v_body)))))
and (* lower.bend:640 *)
f_record_elements : t_RecordTarget -> C.t_Cst -> C.t_Cst -> t_Work =
fun v_target v_fields v_node ->
(let (RecordTarget (v_constructor, v_names)) = v_target in
(RecordElements (v_constructor, v_names, (C.f_field_values (v_fields) (s_69)), [], MTip, v_node)))
and (* lower.bend:644 *)
f_bind : t_Context -> t_Local -> t_Context =
fun v_context v_target ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(let (Local (v_source, v_core)) = v_target in
(Base.bool_pick ((M.f_name_equal (v_source) (s_87))) (v_context) ((Context (v_globals, v_headers, v_fixities, ((Local (v_source, v_core)) :: v_locals), v_label, v_annotation_variables))))))
and (* lower.bend:649 *)
f_bind_all : (t_Local) list -> t_Context -> t_Context =
fun v_locals v_context ->
(match v_locals with
| [] ->
v_context
| (v_local :: v_rest) ->
(f_bind_all (v_rest) ((f_bind (v_context) (v_local)))))
and (* lower.bend:656 *)
f_rebinding_scope : (Base.text) option -> t_Context -> C.t_Cst -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_found v_context v_node ->
(match v_found with
| (Some (v_core)) ->
(Done ((f_bind (v_context) ((Local (s_88, v_core))))))
| None ->
(Fail ((C.f_diagnostic (v_node) (s_89) ((Base.string_append s_90 (C.f_text_of (v_node))))))))
and (* lower.bend:663 *)
f_self_local : (Base.text) option -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_found ->
(match v_found with
| (Some (v_core)) ->
(Done ((M.LocalExpr (v_core))))
| None ->
(Fail ((M.Diagnostic (s_91, s_39, s_92)))))
and (* lower.bend:670 *)
f_self_value : t_Context -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_context ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_variables)) = v_context in
(f_self_local ((f_lookup_local (v_locals) (s_88)))))
and (* lower.bend:674 *)
f_with_label : t_Context -> (int) option -> t_Context =
fun v_context v_label ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_old_label, v_annotation_variables)) = v_context in
(Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)))
and (* lower.bend:678 *)
f_unique_name : C.t_Cst -> Base.text =
fun v_node ->
(Base.string_append (C.f_text_of (v_node)) (Base.string_append s_93 (Base.nat_show ((C.f_offset_of (v_node))))))
and (* lower.bend:682 *)
f_source_annotation : (C.t_Cst) list -> int -> t_Context -> (M.t_Diagnostic, (M.t_Ty) option) Base.result_ =
fun v_nodes v_fuel v_context ->
(match v_nodes with
| [] ->
(Done (None))
| (v_head :: v_tail) ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(T.f_annotation (f_lookup_effect) ((v_head :: v_tail)) (v_fuel) (v_headers) (v_annotation_variables) (v_globals))))
and (* lower.bend:690 *)
f_constraint_type : C.t_Cst -> int -> t_Context -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_node v_fuel v_context ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(match (T.f_lower (f_lookup_effect) (v_fuel) ((T.f_visit (v_node))) (v_headers) (v_annotation_variables) (v_globals)) with
| Fail __error -> Fail __error
| Done v_types ->
(T.f_one (v_types))))
and (* lower.bend:696 *)
f_constraint_types : (C.t_Cst) list -> int -> t_Context -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_nodes v_fuel v_context ->
(match v_nodes with
| [] ->
(Done ([]))
| (v_node :: v_tail) ->
(match (f_constraint_type (v_node) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_constraint_types (v_tail) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_value :: v_rest))))))
and (* lower.bend:706 *)
f_constraint_row : C.t_Cst -> int -> t_Context -> (M.t_Diagnostic, M.t_EffectRow) Base.result_ =
fun v_node v_fuel v_context ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(T.f_row (f_lookup_effect) (v_node) (v_fuel) (v_headers) (v_annotation_variables) (v_globals)))
and (* lower.bend:710 *)
f_constraint_invocation : (C.t_Cst) list -> int -> t_Context -> Base.text -> C.t_Cst -> (M.t_Diagnostic, M.t_EffectRow) Base.result_ =
fun v_nodes v_fuel v_context v_scope v_origin ->
(match v_nodes with
| [] ->
(Done ((M.EffectRow ([], (M.FreeRow (v_scope, (Base.string_append s_94 (Base.nat_show ((C.f_offset_of (v_origin)))))))))))
| (v_row :: []) ->
(f_constraint_row (v_row) (v_fuel) (v_context))
| _ ->
(Fail ((C.f_diagnostic (v_origin) (s_95) (s_96)))))
and (* lower.bend:719 *)
f_constraint_no_row : (C.t_Cst) list -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_nodes v_origin ->
(match v_nodes with
| [] ->
(Done (()))
| _ ->
(Fail ((C.f_diagnostic (v_origin) (s_95) (s_97)))))
and (* lower.bend:726 *)
f_constraint_member : (C.t_Cst) list -> C.t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_nodes v_origin ->
(match v_nodes with
| (v_literal :: []) ->
(C.f_literal (v_literal))
| _ ->
(Fail ((C.f_diagnostic (v_origin) (s_95) (s_98)))))
and (* lower.bend:733 *)
f_constraint_name_children : (C.t_Cst) list -> C.t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_children v_node ->
(match v_children with
| (v_name :: []) ->
(Base.bool_pick ((M.f_name_equal ((C.f_kind_of (v_name))) (s_35))) ((Done ((C.f_name_of (v_name))))) ((Fail ((C.f_diagnostic (v_node) (s_95) (s_99))))))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_95) (s_99)))))
and (* lower.bend:740 *)
f_constraint_name : C.t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_node ->
(f_constraint_name_children ((C.f_children_of (v_node))) (v_node))
and (* lower.bend:743 *)
f_constraint_global : t_Context -> Base.text -> (t_Global) option =
fun v_context v_target ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(f_lookup_global (v_globals) (v_target)))
and (* lower.bend:747 *)
f_constraint_operation : (t_Global) option -> (C.t_Cst) list -> int -> t_Context -> Base.text -> C.t_Cst -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_found v_arguments v_fuel v_context v_scope v_node ->
(match v_found with
| (Some ((Global (v_source, v_core, (OperationTemplateName (v_identity, v_parameters)))))) ->
(match (f_constraint_types (v_arguments) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_types ->
(Done ((M.OperationPredicate (v_identity, v_types, (M.FreeTy (v_scope, (Base.string_append s_100 (Base.nat_show ((C.f_offset_of (v_node))))))))))))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_95) (s_101)))))
and (* lower.bend:756 *)
f_constraint_operation_arguments : (C.t_Cst) list -> int -> t_Context -> Base.text -> C.t_Cst -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_nodes v_fuel v_context v_scope v_node ->
(match v_nodes with
| (v_name :: v_arguments) ->
(match (f_constraint_name (v_name)) with
| Fail __error -> Fail __error
| Done v_target ->
(f_constraint_operation ((f_constraint_global (v_context) (v_target))) (v_arguments) (v_fuel) (v_context) (v_scope) (v_node)))
| [] ->
(Fail ((C.f_diagnostic (v_node) (s_95) (s_102)))))
and (* lower.bend:775 *)
f_constraint_kind : Base.text -> t_ConstraintKind =
fun v_name ->
(Base.bool_pick ((M.f_name_equal (v_name) (s_103))) (AssociatedConstraint) ((Base.bool_pick ((M.f_name_equal (v_name) (s_104))) (ReceiverConstraint) ((Base.bool_pick ((M.f_name_equal (v_name) (s_105))) (FieldConstraint) ((Base.bool_pick ((M.f_name_equal (v_name) (s_106))) (UpdateConstraint) ((Base.bool_pick ((M.f_name_equal (v_name) (s_107))) (OperationConstraint) ((Base.bool_pick ((M.f_name_equal (v_name) (s_108))) (TypeRepConstraint) ((Base.bool_pick ((M.f_name_equal (v_name) (s_109))) (EffectRepConstraint) (UnknownConstraint))))))))))))))
and (* lower.bend:784 *)
f_constraint_predicate_parts : t_ConstraintKind -> Base.text -> (M.t_Ty) list -> (C.t_Cst) list -> int -> t_Context -> Base.text -> C.t_Cst -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_kind v_member v_types v_effects v_fuel v_context v_scope v_node ->
(match (v_kind, v_types) with
| (AssociatedConstraint, (v_left :: (v_right :: (v_result :: [])))) ->
(match (f_constraint_invocation (v_effects) (v_fuel) (v_context) (v_scope) (v_node)) with
| Fail __error -> Fail __error
| Done v_invocation ->
(Done ((M.AssociatedPredicate (v_member, [], v_left, v_right, v_result, v_invocation)))))
| (ReceiverConstraint, (v_receiver :: (v_argument :: (v_result :: [])))) ->
(match (f_constraint_invocation (v_effects) (v_fuel) (v_context) (v_scope) (v_node)) with
| Fail __error -> Fail __error
| Done v_invocation ->
(Done ((M.ReceiverPredicate (v_member, [], v_receiver, v_argument, v_result, v_invocation)))))
| (FieldConstraint, (v_receiver :: (v_result :: []))) ->
(match (f_constraint_no_row (v_effects) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(Done ((M.FieldPredicate (v_member, v_receiver, v_result)))))
| (UpdateConstraint, (v_receiver :: (v_assigned :: (v_result :: [])))) ->
(match (f_constraint_invocation (v_effects) (v_fuel) (v_context) (v_scope) (v_node)) with
| Fail __error -> Fail __error
| Done v_invocation ->
(Done ((M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)))))
| (_, _) ->
(Fail ((C.f_diagnostic (v_node) (s_95) (s_110)))))
and (* lower.bend:805 *)
f_constraint_simple_parts : t_ConstraintKind -> (M.t_Ty) list -> (C.t_Cst) list -> int -> t_Context -> C.t_Cst -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_kind v_types v_effects v_fuel v_context v_node ->
(match (v_kind, v_types, v_effects) with
| (TypeRepConstraint, (v_represented :: []), []) ->
(Done ((M.TypeRepPredicate (v_represented))))
| (EffectRepConstraint, [], (v_row :: [])) ->
(match (f_constraint_row (v_row) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((M.EffectRepPredicate (v_value)))))
| (_, _, _) ->
(Fail ((C.f_diagnostic (v_node) (s_95) (s_111)))))
and (* lower.bend:816 *)
f_constraint_no_member : (C.t_Cst) list -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_nodes v_node ->
(match v_nodes with
| [] ->
(Done (()))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_95) (s_112)))))
and (* lower.bend:823 *)
f_lower_constraint_parts : t_ConstraintKind -> C.t_Cst -> int -> t_Context -> Base.text -> (C.t_Cst) list -> (C.t_Cst) list -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_kind v_node v_fuel v_context v_scope v_arguments v_effects ->
(match v_kind with
| OperationConstraint ->
(match (f_constraint_no_member ((C.f_field_values (v_node) (s_113))) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid_member ->
(match (f_constraint_no_row (v_effects) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_constraint_operation_arguments (v_arguments) (v_fuel) (v_context) (v_scope) (v_node))))
| TypeRepConstraint ->
(match (f_constraint_no_member ((C.f_field_values (v_node) (s_113))) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_constraint_types (v_arguments) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_types ->
(f_constraint_simple_parts (v_kind) (v_types) (v_effects) (v_fuel) (v_context) (v_node))))
| EffectRepConstraint ->
(match (f_constraint_no_member ((C.f_field_values (v_node) (s_113))) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_constraint_types (v_arguments) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_types ->
(f_constraint_simple_parts (v_kind) (v_types) (v_effects) (v_fuel) (v_context) (v_node))))
| _ ->
(match (f_constraint_member ((C.f_field_values (v_node) (s_113))) (v_node)) with
| Fail __error -> Fail __error
| Done v_member ->
(match (f_constraint_types (v_arguments) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_types ->
(f_constraint_predicate_parts (v_kind) (v_member) (v_types) (v_effects) (v_fuel) (v_context) (v_scope) (v_node)))))
and (* lower.bend:846 *)
f_lower_constraint_kind : t_ConstraintKind -> C.t_Cst -> int -> t_Context -> Base.text -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_kind v_node v_fuel v_context v_scope ->
(f_lower_constraint_parts (v_kind) (v_node) (v_fuel) (v_context) (v_scope) ((C.f_field_values (v_node) (s_67))) ((C.f_field_values (v_node) (s_114))))
and (* lower.bend:849 *)
f_constraint_diagnostic : (M.t_Diagnostic, M.t_Predicate) Base.result_ -> C.t_Cst -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_found v_node ->
(match v_found with
| (Done (v_predicate)) ->
(Done (v_predicate))
| (Fail ((M.Diagnostic (v_code, v_subject, v_message)))) ->
(Base.bool_pick ((M.f_name_equal (v_code) (s_115))) ((Fail ((C.f_diagnostic (v_node) (s_116) (s_117))))) ((Fail ((C.f_diagnostic (v_node) (v_code) (v_message)))))))
and (* lower.bend:856 *)
f_lower_constraint_raw : C.t_Cst -> int -> t_Context -> Base.text -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_node v_fuel v_context v_scope ->
(match (C.f_one ((C.f_field_values (v_node) (s_118)))) with
| Fail __error -> Fail __error
| Done v_kind_node ->
(f_lower_constraint_kind ((f_constraint_kind ((C.f_text_of (v_kind_node))))) (v_node) (v_fuel) (v_context) (v_scope)))
and (* lower.bend:861 *)
f_lower_constraint : C.t_Cst -> int -> t_Context -> Base.text -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_node v_fuel v_context v_scope ->
(f_constraint_diagnostic ((f_lower_constraint_raw (v_node) (v_fuel) (v_context) (v_scope))) (v_node))
and (* lower.bend:865 *)
f_lower_constraints : (C.t_Cst) list -> int -> t_Context -> Base.text -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_nodes v_fuel v_context v_scope ->
(match v_nodes with
| [] ->
(Done ([]))
| (v_node :: v_tail) ->
(match (f_lower_constraint (v_node) (v_fuel) (v_context) (v_scope)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_lower_constraints (v_tail) (v_fuel) (v_context) (v_scope)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_first :: v_rest))))))
and (* lower.bend:875 *)
f_where_clause : (M.t_Ty) option -> (C.t_Cst) list -> M.t_Expr -> int -> t_Context -> Base.text -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_annotation v_nodes v_value v_fuel v_context v_scope ->
(match (v_annotation, v_nodes) with
| (_, []) ->
(Done (v_value))
| (None, (v_node :: [])) ->
(Fail ((C.f_diagnostic (v_node) (s_95) (s_119))))
| ((Some (v_ty)), (v_node :: [])) ->
(match (C.f_one ((C.f_field_values (v_node) (s_123)))) with
| Fail __error -> Fail __error
| Done v_marker ->
(match (Base.bool_pick ((M.f_name_equal ((C.f_text_of (v_marker))) (s_121))) ((Done (()))) ((Fail ((C.f_diagnostic (v_marker) (s_95) (s_122)))))) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_lower_constraints ((C.f_field_values (v_node) (s_120))) (v_fuel) (v_context) (v_scope)) with
| Fail __error -> Fail __error
| Done v_predicates ->
(Done ((M.QualifiedExpr ((C.f_offset_of (v_node)), v_ty, v_predicates, v_value)))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_47, s_82, s_124)))))
and (* lower.bend:890 *)
f_parameter_fields : (C.t_Cst) list -> (C.t_Cst) list -> int -> t_Context -> (M.t_Diagnostic, t_Parameter) Base.result_ =
fun v_names v_annotations v_fuel v_context ->
(match v_names with
| [] ->
(Done ((Parameter (s_87, s_125, (Some (M.UnitTy))))))
| (v_name :: []) ->
(match (f_source_annotation (v_annotations) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((Parameter ((C.f_text_of (v_name)), (f_unique_name (v_name)), v_ty)))))
| _ ->
(Fail ((M.Diagnostic (s_47, s_82, s_126)))))
and (* lower.bend:901 *)
f_parameter_rank : (C.t_Cst) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_nodes ->
(match v_nodes with
| [] ->
(Done (()))
| (v_clause :: v_tail) ->
(Fail ((C.f_diagnostic (v_clause) (s_127) (s_128)))))
and (* lower.bend:908 *)
f_lower_parameter : C.t_Cst -> int -> t_Context -> (M.t_Diagnostic, t_Parameter) Base.result_ =
fun v_node v_fuel v_context ->
(match (f_parameter_rank ((C.f_field_values (v_node) (s_121)))) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_parameter_fields ((C.f_field_values (v_node) (s_70))) ((C.f_field_values (v_node) (s_129))) (v_fuel) (v_context)))
and (* lower.bend:913 *)
f_bind_parameter : t_Context -> t_Parameter -> t_Context =
fun v_context v_param ->
(let (Parameter (v_source, v_core, v_annotation)) = v_param in
(f_bind (v_context) ((Local (v_source, v_core)))))
and (* lower.bend:918 *)
f_scalar_intrinsic : Base.text -> C.t_Cst -> (M.t_Diagnostic, t_Primitive) Base.result_ =
fun v_name v_node ->
(Base.bool_pick ((M.f_name_equal (v_name) (s_130))) ((Done ((ScalarPrimitive (M.Add))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_131))) ((Done ((ScalarPrimitive (M.Subtract))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_132))) ((Done ((ScalarPrimitive (M.Multiply))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_133))) ((Done ((ScalarPrimitive (M.Equal))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_134))) ((Done ((ScalarPrimitive (M.LessThan))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_135))) ((Done ((ScalarPrimitive (M.F32Add))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_136))) ((Done ((ScalarPrimitive (M.F32Subtract))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_137))) ((Done ((ScalarPrimitive (M.F32Multiply))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_138))) ((Done ((ScalarPrimitive (M.F32Divide))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_139))) ((Done ((ScalarPrimitive (M.F32Equal))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_140))) ((Done ((ScalarPrimitive (M.F32NotEqual))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_141))) ((Done ((ScalarPrimitive (M.F32LessThan))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_142))) ((Done ((ScalarPrimitive (M.F32LessEqual))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_143))) ((Done ((ScalarPrimitive (M.F32GreaterThan))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_144))) ((Done ((ScalarPrimitive (M.F32GreaterEqual))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_145))) ((Done ((UnaryPrimitive (M.F32Negate))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_146))) ((Done ((UnaryPrimitive (M.F32Absolute))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_147))) ((Done ((UnaryPrimitive (M.F32SquareRoot))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_148))) ((Done ((UnaryPrimitive (M.F32Floor))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_149))) ((Done ((UnaryPrimitive (M.F32Ceiling))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_150))) ((Done ((UnaryPrimitive (M.F32Truncate))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_151))) ((Done ((UnaryPrimitive (M.U32ToF32))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_152))) ((Done ((UnaryPrimitive (M.F32ToU32))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_153))) ((Done (PanicPrimitive))) ((Fail ((C.f_diagnostic (v_node) (s_154) ((Base.string_append s_155 v_name)))))))))))))))))))))))))))))))))))))))))))))))))))))
and (* lower.bend:945 *)
f_ordinary_intrinsic : Base.text -> C.t_Cst -> (M.t_Diagnostic, t_Primitive) Base.result_ =
fun v_name v_node ->
(Base.bool_pick ((M.f_name_equal (v_name) (s_156))) ((Done (ProjectPrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_157))) ((Done (ArrayGeneratePrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_158))) ((Done (ArrayFillPrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_159))) ((Done (ArrayGetPrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_160))) ((Done (ArraySetPrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_161))) ((Done (ArrayLengthPrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_162))) ((Done (StateProviderPrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_163))) ((Done (ProviderPrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_164))) ((Done (OperationDescriptorPrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_165))) ((Done (FunctionEffectsPrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_166))) ((Done (EffectHasPrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_167))) ((Done (EffectCountPrimitive))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_168))) ((Done (EffectSamePrimitive))) ((f_scalar_intrinsic (v_name) (v_node))))))))))))))))))))))))))))
and (* lower.bend:961 *)
f_effect_family_intrinsic : Base.text -> C.t_Cst -> (M.t_Diagnostic, t_Primitive) Base.result_ =
fun v_name v_node ->
(Base.bool_pick ((M.f_name_equal (v_name) (s_169))) ((Done ((EffectFamilyPrimitive (v_name, 2, 2))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_170))) ((Done ((EffectFamilyPrimitive (v_name, 1, 3))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_171))) ((Done ((EffectFamilyPrimitive (v_name, 1, 3))))) ((f_ordinary_intrinsic (v_name) (v_node))))))))
and (* lower.bend:966 *)
f_deferred_intrinsic : Base.text -> C.t_Cst -> (M.t_Diagnostic, t_Primitive) Base.result_ =
fun v_name v_node ->
(Base.bool_pick ((M.f_name_equal (v_name) (s_172))) ((Done ((DeferredPrimitive (v_name, 2))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_173))) ((Done ((DeferredPrimitive (v_name, 1))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_174))) ((Done ((DeferredPrimitive (v_name, 1))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_175))) ((Done ((DeferredPrimitive (v_name, 2))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_176))) ((Done ((DeferredPrimitive (v_name, 3))))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_177))) ((Done ((DeferredPrimitive (v_name, 3))))) ((f_effect_family_intrinsic (v_name) (v_node))))))))))))))
and (* lower.bend:974 *)
f_intrinsic : Base.text -> C.t_Cst -> (M.t_Diagnostic, t_Primitive) Base.result_ =
fun v_name v_node ->
(Base.bool_pick ((M.f_name_equal (v_name) (s_178))) ((Done (AssociatedPrimitive))) ((f_deferred_intrinsic (v_name) (v_node))))
and (* lower.bend:978 *)
f_projection_index_kind : bool -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_valid v_node ->
(match v_valid with
| true ->
(Done (()))
| false ->
(Fail ((C.f_diagnostic (v_node) (s_179) (s_180)))))
and (* lower.bend:985 *)
f_projection_index_children : (C.t_Cst) list -> C.t_Cst -> (M.t_Diagnostic, int) Base.result_ =
fun v_children v_node ->
(match v_children with
| (v_child :: []) ->
(match (f_projection_index_kind ((M.f_name_equal ((C.f_kind_of (v_child))) (s_0))) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (C.f_integer (v_child)) with
| Fail __error -> Fail __error
| Done v_index ->
(Done ((Base.u32_to_nat (v_index))))))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_179) (s_180)))))
and (* lower.bend:995 *)
f_literal_token : bool -> C.t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_valid v_node ->
(match v_valid with
| true ->
(C.f_literal (v_node))
| false ->
(Fail ((C.f_diagnostic (v_node) (s_181) (s_182)))))
and (* lower.bend:1002 *)
f_literal_children : (C.t_Cst) list -> C.t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_children v_node ->
(match v_children with
| (v_child :: []) ->
(f_literal_token ((M.f_name_equal ((C.f_kind_of (v_child))) (s_183))) (v_child))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_181) (s_182)))))
and (* lower.bend:1009 *)
f_literal_argument : C.t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_node ->
(f_literal_children ((C.f_children_of (v_node))) (v_node))
and (* lower.bend:1012 *)
f_operation_specialized_target : t_OperationTarget -> M.t_TypeId -> (M.t_Ty) list -> t_OperationTarget =
fun v_target v_template v_arguments ->
(match v_target with
| (OperationTarget (v_identity, v_previous, v_old_arguments)) ->
(OperationTarget (v_identity, (Some (v_template)), v_arguments)))
and (* lower.bend:1017 *)
f_operation_reference : M.t_Expr -> C.t_Cst -> (M.t_Diagnostic, t_OperationTarget) Base.result_ =
fun v_value v_node ->
(match v_value with
| (M.SourceExpr (v_offset, v_annotation, v_inner)) ->
(f_operation_reference (v_inner) (v_node))
| (M.SpecializeOperationExpr (v_template, v_arguments, v_body)) ->
(match (f_operation_reference (v_body) (v_node)) with
| Fail __error -> Fail __error
| Done v_target ->
(Done ((f_operation_specialized_target (v_target) (v_template) (v_arguments)))))
| (M.OperationExpr (v_identity)) ->
(Done ((OperationTarget (v_identity, None, []))))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_51) (s_184)))))
and (* lower.bend:1030 *)
f_operation_target_identity : t_OperationTarget -> M.t_TypeId =
fun v_target ->
(let (OperationTarget (v_identity, v_template, v_arguments)) = v_target in
v_identity)
and (* lower.bend:1034 *)
f_wrap_operation_target : t_OperationTarget -> M.t_Expr -> M.t_Expr =
fun v_target v_body ->
(match v_target with
| (OperationTarget (v_identity, None, v_arguments)) ->
v_body
| (OperationTarget (v_identity, (Some (v_template)), v_arguments)) ->
(M.SpecializeOperationExpr (v_template, v_arguments, v_body)))
and (* lower.bend:1041 *)
f_foreign_argument_children : (C.t_Cst) list -> bool =
fun v_nodes ->
(match v_nodes with
| (v_node :: []) ->
(Base.bool_and ((M.f_name_equal ((C.f_kind_of (v_node))) (s_35))) ((M.f_name_equal ((C.f_name_of (v_node))) (s_58))))
| _ ->
false)
and (* lower.bend:1048 *)
f_foreign_argument : C.t_Cst -> bool =
fun v_node ->
(f_foreign_argument_children ((C.f_children_of (v_node))))
and (* lower.bend:1051 *)
f_require_unsealed_operation : bool -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_sealed v_node ->
(match v_sealed with
| true ->
(Fail ((C.f_diagnostic (v_node) (s_185) (s_186))))
| false ->
(Done (())))
and (* lower.bend:1058 *)
f_function_reference : M.t_Expr -> C.t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_value v_node ->
(match v_value with
| (M.InstantiationExpr (v_site, v_inner)) ->
(f_function_reference (v_inner) (v_node))
| (M.SourceExpr (v_offset, v_annotation, v_inner)) ->
(f_function_reference (v_inner) (v_node))
| (M.FunctionExpr (v_callee)) ->
(Done (v_callee))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_187) (s_188)))))
and (* lower.bend:1069 *)
f_function_name : C.t_Cst -> t_Context -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_node v_context ->
(match (C.f_one ((C.f_children_of (v_node)))) with
| Fail __error -> Fail __error
| Done v_target ->
(match (f_resolve (v_context) (v_target)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_function_reference (v_value) (v_target))))
and (* lower.bend:1075 *)
f_prefix : (C.t_Cst) list -> M.t_Expr -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_operators v_value ->
(match v_operators with
| [] ->
(Done (v_value))
| ((C.Cst (v_kind, v_field, (SCon (Chr (Base.W32 0x2d), SNil)), v_offset, v_children)) :: []) ->
(Done ((f_located (v_offset) ((M.UnaryExpr (M.F32Negate, v_value))))))
| (v_node :: v_rest) ->
(Fail ((C.f_diagnostic (v_node) (s_189) (s_190)))))
and (* lower.bend:1084 *)
f_constructor_name : M.t_Expr -> C.t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_value v_node ->
(match v_value with
| (M.InstantiationExpr (v_site, v_inner)) ->
(f_constructor_name (v_inner) (v_node))
| (M.SourceExpr (v_offset, v_annotation, v_inner)) ->
(f_constructor_name (v_inner) (v_node))
| (M.ConstructorRefExpr (v_constructor)) ->
(Done (v_constructor))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_74) (s_191)))))
and (* lower.bend:1095 *)
f_pattern_name : C.t_Cst -> t_PatternResult =
fun v_node ->
(let v_source = (C.f_text_of (v_node)) in
(let v_core = (f_unique_name (v_node)) in
(Base.bool_pick ((M.f_name_equal (v_source) (s_87))) ((PatternResult (M.WildcardPattern, []))) ((PatternResult ((M.BindingPattern (v_core)), [(Local (v_source, v_core))]))))))
and (* lower.bend:1100 *)
f_value_pattern : M.t_Expr -> C.t_Cst -> (M.t_Diagnostic, t_PatternResult) Base.result_ =
fun v_reference v_node ->
(match v_reference with
| (M.InstantiationExpr (v_site, v_inner)) ->
(f_value_pattern (v_inner) (v_node))
| (M.SourceExpr (v_offset, v_annotation, v_inner)) ->
(f_value_pattern (v_inner) (v_node))
| (M.LocalExpr (v_name)) ->
(Done ((PatternResult ((M.ValuePattern ((M.LocalReference (v_name)))), []))))
| (M.ConstantExpr (v_name)) ->
(Done ((PatternResult ((M.ValuePattern ((M.ConstantReference (v_name)))), []))))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_192) (s_193)))))
and (* lower.bend:1113 *)
f_pattern_constructor : Base.text -> t_PatternResult -> t_PatternResult =
fun v_constructor v_result ->
(let (PatternResult (v_pattern, v_locals)) = v_result in
(PatternResult ((M.ConstructorPattern (v_constructor, (Some (v_pattern)))), v_locals)))
and (* lower.bend:1117 *)
f_unique_pattern_local : (Base.text) option -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_found v_node ->
(match v_found with
| None ->
(Done (()))
| (Some (v_core)) ->
(Fail ((C.f_diagnostic (v_node) (s_194) (s_195)))))
and (* lower.bend:1124 *)
f_unique_pattern_locals : (t_Local) list -> (t_Local) list -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_locals v_previous v_node ->
(match v_locals with
| [] ->
(Done (()))
| ((Local (v_source, v_core)) :: v_rest) ->
(match (f_unique_pattern_local ((f_lookup_local (v_previous) (v_source))) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_unique_pattern_locals (v_rest) (v_previous) (v_node))))
and (* lower.bend:1133 *)
f_pattern_element : t_PatternResult -> (M.t_Pattern) list -> (t_Local) list -> C.t_Cst -> (M.t_Diagnostic, t_NodeKind) Base.result_ =
fun v_result v_reversed v_previous v_node ->
(let (PatternResult (v_pattern, v_locals)) = v_result in
(match (f_unique_pattern_locals (v_locals) (v_previous) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(Done ((PatternElements ((v_pattern :: v_reversed), (Base.list_append (v_locals) (v_previous))))))))
and (* lower.bend:1139 *)
f_record_pattern_start : t_RecordTarget -> t_NodeKind =
fun v_target ->
(let (RecordTarget (v_constructor, v_fields)) = v_target in
(PatternRecordFields (v_constructor, v_fields, MTip, [])))
and (* lower.bend:1143 *)
f_record_pattern_value : (C.t_Cst) list -> C.t_Cst -> (M.t_Diagnostic, C.t_Cst) Base.result_ =
fun v_values v_name ->
(match v_values with
| [] ->
(Done (v_name))
| (v_value :: []) ->
(Done (v_value))
| _ ->
(Fail ((C.f_diagnostic (v_name) (s_47) (s_196)))))
and (* lower.bend:1152 *)
f_record_pattern_field : t_PatternResult -> Base.text -> (Base.text) list -> (M.t_Pattern) Base.map -> (t_Local) list -> C.t_Cst -> (M.t_Diagnostic, t_NodeKind) Base.result_ =
fun v_result v_constructor v_fields v_patterns v_previous v_name ->
(let (PatternResult (v_pattern, v_locals)) = v_result in
(match (f_unique_pattern_locals (v_locals) (v_previous) (v_name)) with
| Fail __error -> Fail __error
| Done v_valid ->
(Done ((PatternRecordFields (v_constructor, v_fields, (Base.map_set (v_patterns) ((C.f_text_of (v_name))) (v_pattern)), (Base.list_append (v_locals) (v_previous))))))))
and (* lower.bend:1158 *)
f_record_pattern_fields : (Base.text) list -> (M.t_Pattern) Base.map -> (M.t_Pattern) list =
fun v_fields v_patterns ->
(match v_fields with
| [] ->
[]
| (v_name :: v_tail) ->
((Index.f_get (v_patterns) (v_name) (M.WildcardPattern)) :: (f_record_pattern_fields (v_tail) (v_patterns))))
and (* lower.bend:1165 *)
f_record_pattern_result : (M.t_Pattern) list -> Base.text -> (t_Local) list -> t_PatternResult =
fun v_elements v_constructor v_locals ->
(match v_elements with
| [] ->
(PatternResult ((M.ConstructorPattern (v_constructor, None)), v_locals))
| (v_element :: []) ->
(PatternResult ((M.ConstructorPattern (v_constructor, (Some (v_element)))), v_locals))
| (v_first :: (v_second :: v_tail)) ->
(PatternResult ((M.ConstructorPattern (v_constructor, (Some ((M.ProductPattern ((v_first :: (v_second :: v_tail)))))))), v_locals)))
and (* lower.bend:1174 *)
f_lower_pattern : int -> t_NodeKind -> C.t_Cst -> t_Context -> (M.t_Diagnostic, t_PatternResult) Base.result_ =
fun v_fuel v_kind v_node v_context ->
(match v_fuel with
| 0 ->
(Fail ((C.f_diagnostic (v_node) (s_47) (s_197))))
| __nat_13 when __nat_13 >= 1 ->
(let v_remaining = (__nat_13 - 1) in
(match v_kind with
| PatternWrapper ->
(match (C.f_one ((C.f_children_of (v_node)))) with
| Fail __error -> Fail __error
| Done v_child ->
(f_lower_pattern (v_remaining) ((f_classify ((C.f_kind_of (v_child))))) (v_child) (v_context)))
| PatternGroup ->
(f_lower_pattern (v_remaining) (PatternChildren) ((C.Cst (s_46, s_46, s_46, (C.f_offset_of (v_node)), (C.f_field_values (v_node) (s_65))))) (v_context))
| PatternChildren ->
(match v_node with
| (C.Cst (v_kind, v_field, v_text, v_offset, [])) ->
(Done ((PatternResult (M.UnitPattern, []))))
| (C.Cst (v_kind, v_field, v_text, v_offset, (v_child :: []))) ->
(f_lower_pattern (v_remaining) ((f_classify ((C.f_kind_of (v_child))))) (v_child) (v_context))
| (C.Cst (v_kind, v_field, v_text, v_offset, (v_first :: (v_second :: v_tail)))) ->
(f_lower_pattern (v_remaining) ((PatternElements ([], []))) ((C.Cst (v_kind, v_field, v_text, v_offset, (v_first :: (v_second :: v_tail))))) (v_context)))
| (PatternElements (v_reversed, v_locals)) ->
(match v_node with
| (C.Cst (v_kind, v_field, v_text, v_offset, [])) ->
(Done ((PatternResult ((M.ProductPattern ((Base.list_reverse (v_reversed)))), v_locals))))
| (C.Cst (v_kind, v_field, v_text, v_offset, (v_child :: v_tail))) ->
(match (f_lower_pattern (v_remaining) ((f_classify ((C.f_kind_of (v_child))))) (v_child) (v_context)) with
| Fail __error -> Fail __error
| Done v_result ->
(match (f_pattern_element (v_result) (v_reversed) (v_locals) (v_child)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_lower_pattern (v_remaining) (v_next) ((C.Cst (v_kind, v_field, v_text, v_offset, v_tail))) (v_context)))))
| PatternPayload ->
(match v_node with
| (C.Cst (v_kind, v_constructor, v_text, v_offset, [])) ->
(Done ((PatternResult ((M.ConstructorPattern (v_constructor, None)), []))))
| (C.Cst (v_kind, v_constructor, v_text, v_offset, (v_child :: []))) ->
(match (f_lower_pattern (v_remaining) ((f_classify ((C.f_kind_of (v_child))))) (v_child) (v_context)) with
| Fail __error -> Fail __error
| Done v_result ->
(Done ((f_pattern_constructor (v_constructor) (v_result)))))
| _ ->
(Fail ((M.Diagnostic (s_47, s_82, s_198)))))
| PatternValue ->
(match (C.f_one ((C.f_field_values (v_node) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_resolve (v_context) (v_name)) with
| Fail __error -> Fail __error
| Done v_reference ->
(f_value_pattern (v_reference) (v_node))))
| PatternName ->
(Done ((f_pattern_name (v_node))))
| Integer ->
(match (C.f_integer (v_node)) with
| Fail __error -> Fail __error
| Done v_number ->
(Done ((PatternResult ((M.U32Pattern (v_number)), [])))))
| Truth ->
(Done ((PatternResult ((M.BoolPattern (true)), []))))
| Falsehood ->
(Done ((PatternResult ((M.BoolPattern (false)), []))))
| PatternConstructor ->
(f_lower_pattern (v_remaining) ((PatternConstructorForm ((C.f_field_values (v_node) (s_69))))) (v_node) (v_context))
| (PatternConstructorForm ([])) ->
(match (C.f_one ((C.f_field_values (v_node) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (Done ((Base.bool_pick ((M.f_name_equal ((C.f_kind_of (v_name))) (s_200))) ((C.Cst (s_35, s_46, s_46, (C.f_offset_of (v_name)), [v_name]))) (v_name)))) with
| Fail __error -> Fail __error
| Done v_name_node ->
(match (f_resolve (v_context) (v_name_node)) with
| Fail __error -> Fail __error
| Done v_target ->
(match (f_constructor_name (v_target) (v_node)) with
| Fail __error -> Fail __error
| Done v_constructor ->
(f_lower_pattern (v_remaining) (PatternPayload) ((C.Cst (s_199, v_constructor, s_46, (C.f_offset_of (v_node)), (C.f_field_values (v_node) (s_199))))) (v_context))))))
| (PatternConstructorForm ((v_fields :: []))) ->
(match (C.f_one ((C.f_field_values (v_node) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_record_target (v_context) (v_name)) with
| Fail __error -> Fail __error
| Done v_target ->
(f_lower_pattern (v_remaining) ((f_record_pattern_start (v_target))) ((C.Cst (s_201, s_46, s_46, (C.f_offset_of (v_fields)), (C.f_field_values (v_fields) (s_69))))) (v_context))))
| (PatternConstructorForm (v_fields)) ->
(Fail ((C.f_diagnostic (v_node) (s_47) (s_202))))
| (PatternRecordFields (v_constructor, v_fields, v_patterns, v_locals)) ->
(match v_node with
| (C.Cst (v_kind, v_field, v_text, v_offset, [])) ->
(Done ((f_record_pattern_result ((f_record_pattern_fields (v_fields) (v_patterns))) (v_constructor) (v_locals))))
| (C.Cst (v_kind, v_field, v_text, v_offset, (v_child :: v_tail))) ->
(match (C.f_one ((C.f_field_values (v_child) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_record_field_valid ((f_record_field_present (v_fields) ((C.f_text_of (v_name))))) ((Base.maybe_is_some ((Index.f_find (v_patterns) ((C.f_text_of (v_name))))))) (v_name)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_record_pattern_value ((C.f_field_values (v_child) (s_65))) (v_name)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_lower_pattern (v_remaining) ((f_classify ((C.f_kind_of (v_value))))) (v_value) (v_context)) with
| Fail __error -> Fail __error
| Done v_result ->
(match (f_record_pattern_field (v_result) (v_constructor) (v_fields) (v_patterns) (v_locals) (v_name)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_lower_pattern (v_remaining) (v_next) ((C.Cst (v_kind, v_field, v_text, v_offset, v_tail))) (v_context))))))))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_203) (s_204)))))))
and (* lower.bend:1259 *)
f_combine_pattern_row : t_PatternResult -> t_PatternRow -> C.t_Cst -> (M.t_Diagnostic, t_PatternRow) Base.result_ =
fun v_first v_next v_node ->
(let (PatternResult (v_pattern, v_locals)) = v_first in
(let (PatternRow (v_patterns, v_following)) = v_next in
(match (f_unique_pattern_locals (v_locals) (v_following) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(Done ((PatternRow ((v_pattern :: v_patterns), (Base.list_append (v_locals) (v_following)))))))))
and (* lower.bend:1266 *)
f_row_patterns : t_PatternRow -> (M.t_Pattern) list =
fun v_row ->
(let (PatternRow (v_patterns, v_locals)) = v_row in
v_patterns)
and (* lower.bend:1270 *)
f_row_scope : t_Context -> t_PatternRow -> t_Context =
fun v_context v_row ->
(let (PatternRow (v_patterns, v_locals)) = v_row in
(f_bind_all (v_locals) (v_context)))
and (* lower.bend:1274 *)
f_lower_pattern_row : (C.t_Cst) list -> int -> t_Context -> (M.t_Diagnostic, t_PatternRow) Base.result_ =
fun v_nodes v_fuel v_context ->
(match v_nodes with
| [] ->
(Done ((PatternRow ([], []))))
| (v_node :: v_tail) ->
(match (f_lower_pattern (v_fuel) ((f_classify ((C.f_kind_of (v_node))))) (v_node) (v_context)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_lower_pattern_row (v_tail) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_combine_pattern_row (v_first) (v_next) (v_node)))))
and (* lower.bend:1284 *)
f_descriptor_argument : int -> M.t_Expr -> M.t_Expr =
fun v_fuel v_value ->
(match (v_fuel, v_value) with
| (__nat_14, (M.SourceExpr (v_offset, v_annotation, v_inner))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(M.SourceExpr (v_offset, v_annotation, (f_descriptor_argument (v_rest) (v_inner)))))
| (__nat_15, (M.SpecializeOperationExpr (v_template, v_arguments, v_inner))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(M.SpecializeOperationExpr (v_template, v_arguments, (f_descriptor_argument (v_rest) (v_inner)))))
| (_, (M.OperationExpr (v_identity))) ->
(M.OperationDescriptorExpr (v_identity))
| (_, v_other) ->
v_other)
and (* lower.bend:1295 *)
f_statement_nodes : C.t_Cst -> (C.t_Cst) list =
fun v_node ->
(C.f_field_values (v_node) (s_205))
and (* lower.bend:1298 *)
f_else_statements : (C.t_Cst) list -> (M.t_Diagnostic, (C.t_Cst) list) Base.result_ =
fun v_nodes ->
(match v_nodes with
| [] ->
(Done ([]))
| (v_node :: []) ->
(match (C.f_one ((C.f_field_values (v_node) (s_206)))) with
| Fail __error -> Fail __error
| Done v_suite ->
(Done ((f_statement_nodes (v_suite)))))
| _ ->
(Fail ((M.Diagnostic (s_47, s_82, s_207)))))
and (* lower.bend:1309 *)
f_reachable : (C.t_Cst) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_nodes ->
(match v_nodes with
| [] ->
(Done (()))
| (v_node :: v_tail) ->
(Fail ((C.f_diagnostic (v_node) (s_208) (s_209)))))
and (* lower.bend:1316 *)
f_require_plain_return : (C.t_Cst) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_markers ->
(match v_markers with
| [] ->
(Done (()))
| (v_node :: v_tail) ->
(Fail ((C.f_diagnostic (v_node) (s_210) (s_211)))))
and (* lower.bend:1323 *)
f_returning : t_Context -> M.t_Expr -> C.t_Cst -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_context v_value v_node ->
(match v_context with
| (Context (v_globals, v_headers, v_fixities, v_locals, (Some (v_label)), v_annotation_variables)) ->
(Done ((M.ReturnExpr (v_label, v_value))))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_212) (s_213)))))
and (* lower.bend:1330 *)
f_lambda : int -> t_Parameter -> (M.t_Ty) option -> M.t_Expr -> M.t_Expr =
fun v_identity v_param v_result v_body ->
(let (Parameter (v_source, v_core, v_annotation)) = v_param in
(M.LambdaExpr (v_identity, v_core, v_annotation, v_result, v_body)))
and (* lower.bend:1334 *)
f_plain_binding : M.t_Pattern -> M.t_Expr -> M.t_Expr -> int -> M.t_Expr =
fun v_pattern v_value v_body v_offset ->
(match v_pattern with
| (M.BindingPattern (v_name)) ->
(M.LetExpr (v_name, v_value, v_body))
| M.WildcardPattern ->
(M.LetExpr ((Base.string_append s_214 (Base.nat_show (v_offset))), v_value, v_body))
| v_pattern ->
(let v_temporary = (Base.string_append s_215 (Base.nat_show (v_offset))) in
(M.LetExpr (v_temporary, v_value, (M.MatchExpr ([(M.LocalExpr (v_temporary))], [(M.MatchArm ([v_pattern], v_body))]))))))
and (* lower.bend:1344 *)
f_binding : bool -> M.t_Pattern -> M.t_Expr -> M.t_Expr -> M.t_Expr -> int -> M.t_Expr =
fun v_guarded v_pattern v_value v_alternative v_body v_offset ->
(match v_guarded with
| true ->
(M.GuardExpr (v_pattern, v_value, v_alternative, v_body))
| false ->
(f_plain_binding (v_pattern) (v_value) (v_body) (v_offset)))
and (* lower.bend:1351 *)
f_effect_target : (C.t_Cst) list -> int -> (M.t_Diagnostic, t_Local) Base.result_ =
fun v_names v_offset ->
(match v_names with
| [] ->
(Done ((Local (s_87, (Base.string_append s_214 (Base.nat_show (v_offset)))))))
| (v_name :: []) ->
(Done ((Local ((C.f_text_of (v_name)), (f_unique_name (v_name))))))
| _ ->
(Fail ((M.Diagnostic (s_47, s_82, s_216)))))
and (* lower.bend:1360 *)
f_effect_binding : t_Local -> M.t_Expr -> M.t_Expr -> M.t_Expr =
fun v_target v_value v_body ->
(let (Local (v_source, v_core)) = v_target in
(M.UseExpr (v_core, v_value, v_body)))
and (* lower.bend:1364 *)
f_pattern_of : t_PatternResult -> M.t_Pattern =
fun v_result ->
(let (PatternResult (v_pattern, v_locals)) = v_result in
v_pattern)
and (* lower.bend:1368 *)
f_loop_pattern : int -> (C.t_Cst) list -> t_Context -> (M.t_Diagnostic, t_PatternResult) Base.result_ =
fun v_fuel v_nodes v_context ->
(match v_nodes with
| [] ->
(Done ((PatternResult (M.WildcardPattern, []))))
| (v_node :: []) ->
(f_lower_pattern (v_fuel) ((f_classify ((C.f_kind_of (v_node))))) (v_node) (v_context))
| _ ->
(Fail ((M.Diagnostic (s_47, s_217, s_218)))))
and (* lower.bend:1377 *)
f_pattern_scope : t_Context -> t_PatternResult -> t_Context =
fun v_context v_result ->
(let (PatternResult (v_pattern, v_locals)) = v_result in
(f_bind_all (v_locals) (v_context)))
and (* lower.bend:1381 *)
f_symbolic_operator : (O.t_Fixity) option -> C.t_Cst -> (M.t_Diagnostic, O.t_Operator) Base.result_ =
fun v_found v_node ->
(match v_found with
| (Some (v_fixity)) ->
(Done ((O.f_from_fixity (v_fixity) ((C.f_offset_of (v_node))))))
| None ->
(Fail ((C.f_diagnostic (v_node) (s_219) ((Base.string_append s_220 (C.f_text_of (v_node))))))))
and (* lower.bend:1388 *)
f_named_operator : (O.t_Fixity) option -> M.t_Expr -> int -> O.t_Operator =
fun v_found v_target v_offset ->
(match v_found with
| (Some ((O.Fixity (v_name, v_named, v_precedence, v_association, v_ignored)))) ->
(O.Operator (v_precedence, v_association, v_target, v_offset))
| None ->
(O.Operator ((Base.W32 0x50), O.Left, v_target, v_offset)))
and (* lower.bend:1395 *)
f_context_fixities : t_Context -> (O.t_Fixity) list =
fun v_context ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
v_fixities)
and (* lower.bend:1399 *)
f_source_operator : t_NodeKind -> C.t_Cst -> t_Context -> (M.t_Diagnostic, O.t_Operator) Base.result_ =
fun v_kind v_node v_context ->
(match v_kind with
| NamedFixity ->
(match (C.f_one ((C.f_field_values (v_node) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_resolve (v_context) (v_name)) with
| Fail __error -> Fail __error
| Done v_target ->
(Done ((f_named_operator ((O.f_lookup ((f_context_fixities (v_context))) ((C.f_name_of (v_name))) (true))) (v_target) ((C.f_offset_of (v_node))))))))
| _ ->
(f_symbolic_operator ((O.f_lookup ((f_context_fixities (v_context))) ((C.f_text_of (v_node))) (false))) (v_node)))
and (* lower.bend:1409 *)
f_operator_kind : C.t_Cst -> t_NodeKind =
fun v_node ->
(Base.bool_pick ((M.f_name_equal ((C.f_kind_of (v_node))) (s_221))) (NamedFixity) (SymbolicFixity))
and (* lower.bend:1412 *)
f_pattern_locals : t_PatternResult -> (t_Local) list =
fun v_result ->
(let (PatternResult (v_pattern, v_locals)) = v_result in
v_locals)
and (* lower.bend:1416 *)
f_shadow_names : (t_Local) list -> Base.set -> Base.set =
fun v_locals v_shadowed ->
(match v_locals with
| [] ->
v_shadowed
| ((Local (v_source, v_core)) :: v_tail) ->
(f_shadow_names (v_tail) ((Base.set_add (v_shadowed) (v_source)))))
and (* lower.bend:1423 *)
f_target_name : Base.text -> Base.set -> Base.set -> Base.set =
fun v_name v_shadowed v_targets ->
(Base.bool_pick ((Base.maybe_is_some ((Index.f_find (v_shadowed) (v_name))))) (v_targets) ((Base.set_add (v_targets) (v_name))))
and (* lower.bend:1432 *)
f_loop_targets : int -> t_LoopTargetsWork -> t_Context -> Base.set -> Base.set -> (M.t_Diagnostic, Base.set) Base.result_ =
fun v_fuel v_work v_context v_shadowed v_targets ->
(match (v_fuel, v_work) with
| (_, (LoopTargets ([]))) ->
(Done (v_targets))
| (0, _) ->
(Fail ((M.Diagnostic (s_222, s_217, s_223))))
| (__nat_16, (LoopTargets ((v_statement :: v_tail)))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(match (C.f_one ((C.f_field_values (v_statement) (s_65)))) with
| Fail __error -> Fail __error
| Done v_node ->
(f_loop_targets (v_rest) ((LoopTarget ((f_classify ((C.f_kind_of (v_node)))), v_node, v_tail))) (v_context) (v_shadowed) (v_targets))))
| (__nat_17, (LoopTarget (Rebinding, v_node, v_tail))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(match (C.f_one ((C.f_field_values (v_node) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name ->
(f_loop_targets (v_rest) ((LoopTargets (v_tail))) (v_context) (v_shadowed) ((f_target_name ((C.f_text_of (v_name))) (v_shadowed) (v_targets))))))
| (__nat_18, (LoopTarget (Binding, v_node, v_tail))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(match (C.f_one ((C.f_field_values (v_node) (s_31)))) with
| Fail __error -> Fail __error
| Done v_pattern ->
(match (f_lower_pattern (v_rest) ((f_classify ((C.f_kind_of (v_pattern))))) (v_pattern) (v_context)) with
| Fail __error -> Fail __error
| Done v_parsed ->
(f_loop_targets (v_rest) ((LoopTargets (v_tail))) ((f_pattern_scope (v_context) (v_parsed))) ((f_shadow_names ((f_pattern_locals (v_parsed))) (v_shadowed))) (v_targets)))))
| (__nat_19, (LoopTarget (EffectBinding, v_node, v_tail))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(match (f_effect_target ((C.f_field_values (v_node) (s_70))) ((C.f_offset_of (v_node)))) with
| Fail __error -> Fail __error
| Done v_target ->
(f_loop_targets (v_rest) ((LoopTargets (v_tail))) ((f_bind (v_context) (v_target))) ((f_shadow_names ([v_target]) (v_shadowed))) (v_targets))))
| (__nat_20, (LoopTarget (ForLoop, v_node, v_tail))) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(match (f_loop_pattern (v_rest) ((C.f_field_values (v_node) (s_31))) (v_context)) with
| Fail __error -> Fail __error
| Done v_parsed ->
(match (C.f_one ((C.f_field_values (v_node) (s_224)))) with
| Fail __error -> Fail __error
| Done v_suite ->
(match (f_loop_targets (v_rest) ((LoopTargets ((f_statement_nodes (v_suite))))) ((f_pattern_scope (v_context) (v_parsed))) ((f_shadow_names ((f_pattern_locals (v_parsed))) (v_shadowed))) (v_targets)) with
| Fail __error -> Fail __error
| Done v_nested ->
(f_loop_targets (v_rest) ((LoopTargets (v_tail))) (v_context) (v_shadowed) (v_nested))))))
| (__nat_21, (LoopTarget (v_kind, v_node, v_tail))) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(f_loop_targets (v_rest) ((LoopTargets (v_tail))) (v_context) (v_shadowed) (v_targets))))
and (* lower.bend:1464 *)
f_carried_locals : (t_Local) list -> Base.set -> Base.set -> (t_Local) list =
fun v_locals v_targets v_seen ->
(match v_locals with
| [] ->
[]
| (v_local :: v_tail) ->
(let (Local (v_source, v_core)) = v_local in
(let v_keep = (Base.bool_and ((Base.maybe_is_some ((Index.f_find (v_targets) (v_source))))) ((Base.bool_not ((Base.maybe_is_some ((Index.f_find (v_seen) (v_source)))))))) in
(let v_rest = (f_carried_locals (v_tail) (v_targets) ((Base.set_add (v_seen) (v_source)))) in
(Base.bool_pick (v_keep) ((v_local :: v_rest)) (v_rest))))))
and (* lower.bend:1474 *)
f_loop_locals : t_Context -> Base.set -> (t_Local) list =
fun v_context v_targets ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(f_carried_locals (v_locals) (v_targets) ((Base.set_new ()))))
and (* lower.bend:1478 *)
f_loop_value : (M.t_Expr) list -> M.t_Expr =
fun v_elements ->
(match v_elements with
| [] ->
M.UnitExpr
| (v_value :: []) ->
v_value
| v_elements ->
(M.ProductExpr (v_elements)))
and (* lower.bend:1487 *)
f_local_values : (t_Local) list -> (M.t_Expr) list =
fun v_locals ->
(match v_locals with
| [] ->
[]
| ((Local (v_source, v_core)) :: v_tail) ->
((M.LocalExpr (v_core)) :: (f_local_values (v_tail))))
and (* lower.bend:1494 *)
f_loop_versions : (t_Local) list -> Base.text -> (t_Local) list =
fun v_locals v_prefix ->
(match v_locals with
| [] ->
[]
| ((Local (v_source, v_core)) :: v_tail) ->
((Local (v_source, (Base.string_append v_prefix v_source))) :: (f_loop_versions (v_tail) (v_prefix))))
and (* lower.bend:1501 *)
f_loop_bindings : (t_Local) list -> Base.text -> int -> bool -> M.t_Expr -> M.t_Expr =
fun v_locals v_state v_index v_single v_body ->
(match v_locals with
| [] ->
v_body
| ((Local (v_source, v_core)) :: v_tail) ->
(M.UseExpr (v_core, (Base.bool_pick (v_single) ((M.LocalExpr (v_state))) ((M.ProjectExpr ((M.LocalExpr (v_state)), v_index)))), (f_loop_bindings (v_tail) (v_state) ((Base.nat_add 1 v_index)) (v_single) (v_body)))))
and (* lower.bend:1508 *)
f_successor_carried : (t_Local) list -> (Base.text) option -> Base.text -> (t_Local) list =
fun v_carried v_previous v_next ->
(match (v_carried, v_previous) with
| ([], _) ->
[]
| (v_carried, None) ->
v_carried
| (((Local (v_source, v_core)) :: v_tail), (Some (v_old))) ->
((Local (v_source, (Base.bool_pick ((M.f_name_equal (v_core) (v_old))) (v_next) (v_core)))) :: (f_successor_carried (v_tail) (v_previous) (v_next))))
and (* lower.bend:1517 *)
f_loop_carried : (t_Local) list -> (t_Local) list -> (t_Local) list -> (t_Local) list =
fun v_originals v_versions v_carried ->
(match (v_originals, v_versions) with
| (((Local (v_source, v_previous)) :: v_old_tail), ((Local (v_next_source, v_next)) :: v_next_tail)) ->
(f_loop_carried (v_old_tail) (v_next_tail) ((f_successor_carried (v_carried) ((Some (v_previous))) (v_next))))
| (_, _) ->
v_carried)
and (* lower.bend:1524 *)
f_application_children : t_NodeKind -> C.t_Cst -> (C.t_Cst) list =
fun v_kind v_node ->
(match v_kind with
| Wrapper ->
(C.f_children_of (v_node))
| GroupNode ->
(C.f_field_values (v_node) (s_65))
| InfixNode ->
(Base.bool_pick ((Base.list_is_empty ((C.f_field_values (v_node) (s_71))))) ((C.f_field_values (v_node) (s_66))) ([]))
| PrefixNode ->
(Base.bool_pick ((Base.list_is_empty ((C.f_field_values (v_node) (s_72))))) ((C.f_field_values (v_node) (s_65))) ([]))
| _ ->
[])
and (* lower.bend:1544 *)
f_grouped_operation : int -> t_GroupedOperation -> (C.t_Cst) list -> t_Context -> (M.t_Diagnostic, (t_TypedCall) option) Base.result_ =
fun v_fuel v_work v_arguments v_context ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_225, s_82, s_226))))
| (__nat_22, (OperationHead (ApplicationNode, v_node))) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(f_grouped_operation (v_rest) ((OperationChildren ((C.f_field_values (v_node) (s_66))))) ((Base.list_append ((C.f_field_values (v_node) (s_67))) (v_arguments))) (v_context)))
| (__nat_23, (OperationHead (RecordNode, v_node))) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(match (C.f_one ((C.f_field_values (v_node) (s_69)))) with
| Fail __error -> Fail __error
| Done v_fields ->
(f_grouped_operation (v_rest) ((OperationChildren ((C.f_field_values (v_node) (s_70))))) ((v_fields :: v_arguments)) (v_context))))
| (__nat_24, (OperationHead (Name, v_node))) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(f_grouped_operation (v_rest) ((OperationTemplate ((f_template_reference ((f_lookup_local (v_locals) ((C.f_name_of (v_node))))) ((f_lookup_global (v_globals) ((C.f_name_of (v_node)))))), v_node))) (v_arguments) (v_context))))
| (__nat_25, (OperationHead (v_kind, v_node))) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(f_grouped_operation (v_rest) ((OperationChildren ((f_application_children (v_kind) (v_node))))) (v_arguments) (v_context)))
| (__nat_26, (OperationChildren ((v_node :: [])))) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(f_grouped_operation (v_rest) ((OperationHead ((f_classify ((C.f_kind_of (v_node)))), v_node))) (v_arguments) (v_context)))
| (__nat_27, (OperationChildren (v_nodes))) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(Done (None)))
| (__nat_28, (OperationTemplate (None, v_node))) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(Done (None)))
| (__nat_29, (OperationTemplate ((Some (v_template)), v_node))) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(match (f_typed_operation_value (v_template) (v_arguments) (v_rest) (v_context) (v_node)) with
| Fail __error -> Fail __error
| Done v_call ->
(Done ((Some (v_call)))))))
and (* lower.bend:1572 *)
f_terminal_update_field : (M.t_Diagnostic, (Base.text) list) Base.result_ -> Base.text -> M.t_Expr -> M.t_Expr -> M.t_Expr =
fun v_free v_name v_receiver v_value ->
(match v_free with
| (Done (v_names)) ->
(Base.bool_pick ((Closures.f_contains (v_names) (v_name))) ((M.UseExpr (v_name, v_receiver, v_value))) (v_value))
| (Fail (v_diagnostic)) ->
(M.UseExpr (v_name, v_receiver, v_value)))
and (* lower.bend:1579 *)
f_terminal_update_value : M.t_Expr -> Base.text -> M.t_Expr -> M.t_Expr =
fun v_receiver v_name v_value ->
(match v_receiver with
| (M.AssociatedExpr (v_identity, M.MemberDispatch, v_member, v_templates, v_left, v_right)) ->
(f_terminal_update_field ((Closures.f_free (4096) ((Closures.ExpressionWork (v_value, []))))) (v_name) ((M.AssociatedExpr (v_identity, M.MemberDispatch, v_member, v_templates, v_left, v_right))) (v_value))
| v_other ->
(M.UseExpr (v_name, v_other, v_value)))
and (* lower.bend:1594 *)
f_annotation_scan_work : int -> t_AnnotationScan -> (M.t_Diagnostic, (C.t_Cst) list) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_225, s_82, s_227))))
| (__nat_30, (ScanNode ((C.Cst ((SCon (Chr (Base.W32 0x62), (SCon (Chr (Base.W32 0x69), (SCon (Chr (Base.W32 0x6e), (SCon (Chr (Base.W32 0x64), (SCon (Chr (Base.W32 0x69), (SCon (Chr (Base.W32 0x6e), (SCon (Chr (Base.W32 0x67), SNil)))))))))))))), v_field, v_text, v_offset, v_children)), false))) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(Done ([(C.Cst (s_9, v_field, v_text, v_offset, []))])))
| (__nat_31, (ScanNode ((C.Cst (v_kind, v_field, v_text, v_offset, v_children)), v_root))) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(match (f_annotation_scan_work (v_rest) ((ScanNodes (v_children, [])))) with
| Fail __error -> Fail __error
| Done v_scoped ->
(Done ([(C.Cst (v_kind, v_field, v_text, v_offset, v_scoped))]))))
| (__nat_32, (ScanNodes ([], v_reversed))) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(Done ((Base.list_reverse (v_reversed)))))
| (__nat_33, (ScanNodes ((v_head :: v_tail), v_reversed))) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(match (f_annotation_scan_work (v_rest) ((ScanNode (v_head, false)))) with
| Fail __error -> Fail __error
| Done v_scanned ->
(match (C.f_one (v_scanned)) with
| Fail __error -> Fail __error
| Done v_node ->
(f_annotation_scan_work (v_rest) ((ScanNodes (v_tail, (v_node :: v_reversed)))))))))
and (* lower.bend:1612 *)
f_inherited_annotation_kind : bool -> Base.text -> M.t_Ty -> T.t_VariableKind -> C.t_Cst -> (M.t_Diagnostic, T.t_Variable) Base.result_ =
fun v_same v_source v_value v_kind v_node ->
(match v_same with
| true ->
(Done ((T.Variable (v_source, v_value, v_kind))))
| false ->
(Fail ((C.f_diagnostic (v_node) (s_228) (s_229)))))
and (* lower.bend:1619 *)
f_inherited_annotation_variable : (T.t_Variable) option -> T.t_Variable -> C.t_Cst -> (M.t_Diagnostic, T.t_Variable) Base.result_ =
fun v_found v_scanned v_node ->
(match (v_found, v_scanned) with
| (None, v_variable) ->
(Done (v_variable))
| ((Some ((T.Variable (v_previous_name, v_previous_value, v_previous_kind)))), (T.Variable (v_source, v_value, v_kind))) ->
(f_inherited_annotation_kind ((T.f_same_kind (v_previous_kind) (v_kind))) (v_source) (v_previous_value) (v_kind) (v_node)))
and (* lower.bend:1626 *)
f_inherited_annotation_variables : (T.t_Variable) list -> (T.t_Variable) list -> C.t_Cst -> (M.t_Diagnostic, (T.t_Variable) list) Base.result_ =
fun v_scanned v_previous v_node ->
(match v_scanned with
| [] ->
(Done (v_previous))
| ((T.Variable (v_source, v_value, v_kind)) :: v_tail) ->
(match (f_inherited_annotation_variable ((T.f_found_variable (v_previous) (v_source))) ((T.Variable (v_source, v_value, v_kind))) (v_node)) with
| Fail __error -> Fail __error
| Done v_variable ->
(match (f_inherited_annotation_variables (v_tail) (v_previous) (v_node)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_variable :: v_rest))))))
and (* lower.bend:1636 *)
f_annotation_scope : C.t_Cst -> t_Context -> Base.text -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_node v_context v_scope ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_previous)) = v_context in
(match (f_annotation_scan_work (1048576) ((ScanNode (v_node, true)))) with
| Fail __error -> Fail __error
| Done v_scoped ->
(match (C.f_one (v_scoped)) with
| Fail __error -> Fail __error
| Done v_root ->
(match (T.f_free_variables (v_root) (v_scope)) with
| Fail __error -> Fail __error
| Done v_scanned ->
(match (f_inherited_annotation_variables (v_scanned) (v_previous) (v_node)) with
| Fail __error -> Fail __error
| Done v_variables ->
(Done ((Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_variables)))))))))
and (* lower.bend:1645 *)
f_lower : int -> t_Work -> t_Context -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_fuel v_work v_context ->
(match v_fuel with
| 0 ->
(Fail ((M.Diagnostic (s_47, s_82, s_230))))
| __nat_34 when __nat_34 >= 1 ->
(let v_remaining = (__nat_34 - 1) in
(match v_work with
| (Expression (Wrapper, v_node)) ->
(match (C.f_one ((C.f_children_of (v_node)))) with
| Fail __error -> Fail __error
| Done v_child ->
(f_lower (v_remaining) ((f_visit (v_child))) (v_context)))
| (Expression (Integer, v_node)) ->
(match (C.f_integer (v_node)) with
| Fail __error -> Fail __error
| Done v_number ->
(Done ((f_located ((C.f_offset_of (v_node))) ((M.U32Expr (v_number)))))))
| (Expression (Float, v_node)) ->
(match (C.f_float (v_node)) with
| Fail __error -> Fail __error
| Done v_number ->
(Done ((f_located ((C.f_offset_of (v_node))) ((M.F32Expr (v_number)))))))
| (Expression (PrefixNode, v_node)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_65)))) with
| Fail __error -> Fail __error
| Done v_child ->
(match (f_lower (v_remaining) ((f_visit (v_child))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_prefix ((C.f_field_values (v_node) (s_72))) (v_value))))
| (Expression (Truth, v_node)) ->
(Done ((f_located ((C.f_offset_of (v_node))) ((M.BoolExpr (true))))))
| (Expression (Falsehood, v_node)) ->
(Done ((f_located ((C.f_offset_of (v_node))) ((M.BoolExpr (false))))))
| (Expression (Name, v_node)) ->
(match (f_resolve (v_context) (v_node)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_located ((C.f_offset_of (v_node))) (v_value)))))
| (Expression (GroupNode, v_node)) ->
(f_lower (v_remaining) ((Group ((C.f_field_values (v_node) (s_65)), (C.f_offset_of (v_node))))) (v_context))
| (Group ([], v_offset)) ->
(Done ((f_located (v_offset) (M.UnitExpr))))
| (Group ((v_node :: []), v_offset)) ->
(f_lower (v_remaining) ((f_visit (v_node))) (v_context))
| (Group ((v_head :: (v_next :: v_rest)), v_offset)) ->
(f_lower (v_remaining) ((ProductElements ((v_head :: (v_next :: v_rest)), [], v_offset))) (v_context))
| (ProductElements ([], v_reversed, v_offset)) ->
(Done ((f_located (v_offset) ((M.ProductExpr ((Base.list_reverse (v_reversed))))))))
| (ProductElements ((v_head :: v_tail), v_reversed, v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_head))) (v_context)) with
| Fail __error -> Fail __error
| Done v_element ->
(f_lower (v_remaining) ((ProductElements (v_tail, (v_element :: v_reversed), v_offset))) (v_context)))
| (Expression (ArrayNode, v_node)) ->
(f_lower (v_remaining) ((ArrayElements ((C.f_field_values (v_node) (s_68)), [], (C.f_offset_of (v_node))))) (v_context))
| (ArrayElements ([], v_reversed, v_offset)) ->
(Done ((f_located (v_offset) ((M.ArrayExpr ((Base.list_reverse (v_reversed))))))))
| (ArrayElements ((v_head :: v_tail), v_reversed, v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_head))) (v_context)) with
| Fail __error -> Fail __error
| Done v_element ->
(f_lower (v_remaining) ((ArrayElements (v_tail, (v_element :: v_reversed), v_offset))) (v_context)))
| (Expression (RecordNode, v_node)) ->
(f_lower (v_remaining) ((ApplicationHead (RecordNode, v_node, [], (C.f_offset_of (v_node))))) (v_context))
| (RecordElements (v_constructor, v_fields, [], v_reversed, v_seen, v_node)) ->
(match (f_record_payload_elements (v_fields) (v_reversed) (v_node) ([])) with
| Fail __error -> Fail __error
| Done v_payload ->
(Done ((f_located ((C.f_offset_of (v_node))) ((f_record_bindings (v_reversed) ((M.ConstructExpr (v_constructor, (f_record_payload (v_payload)))))))))))
| (RecordElements (v_constructor, v_fields, (v_field :: v_tail), v_reversed, v_seen, v_node)) ->
(match (C.f_one ((C.f_field_values (v_field) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name_node ->
(match (Done ((C.f_text_of (v_name_node)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_record_field_valid ((f_record_field_present (v_fields) (v_name))) ((Base.maybe_is_some ((Index.f_find (v_seen) (v_name))))) (v_name_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_record_value_node ((C.f_field_values (v_field) (s_65))) (v_name_node)) with
| Fail __error -> Fail __error
| Done v_value_node ->
(match (f_lower (v_remaining) ((f_visit (v_value_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (Done ((Base.string_append s_231 (Base.nat_show ((C.f_offset_of (v_field))))))) with
| Fail __error -> Fail __error
| Done v_temporary ->
(f_lower (v_remaining) ((RecordElements (v_constructor, v_fields, v_tail, ((RecordElement (v_name, v_temporary, v_value)) :: v_reversed), (Base.set_add (v_seen) (v_name)), v_node))) (v_context))))))))
| (Expression (MemberNode, v_node)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_104)))) with
| Fail __error -> Fail __error
| Done v_receiver_node ->
(match (C.f_one ((C.f_field_values (v_node) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_lower (v_remaining) ((f_visit (v_receiver_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_receiver ->
(let v_offset = (C.f_offset_of (v_name)) in
(Done ((f_located (v_offset) ((f_instantiate_at (v_offset) (2) ((M.AssociatedExpr (v_offset, M.MemberDispatch, (C.f_text_of (v_name)), [], v_receiver, M.UnitExpr))))))))))))
| (Expression (IndexNode, v_node)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_104)))) with
| Fail __error -> Fail __error
| Done v_receiver_node ->
(match (C.f_one ((C.f_field_values (v_node) (s_232)))) with
| Fail __error -> Fail __error
| Done v_index_node ->
(match (f_lower (v_remaining) ((f_visit (v_receiver_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_receiver ->
(match (f_lower (v_remaining) ((f_visit (v_index_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_index ->
(Done ((f_located ((C.f_offset_of (v_node))) ((M.ArrayGetExpr (v_receiver, v_index))))))))))
| (Expression (ApplicationNode, v_node)) ->
(match (Postfix.f_application (v_node)) with
| Fail __error -> Fail __error
| Done v_parts ->
(match (C.f_one ((C.f_children_of ((Postfix.f_head (v_parts)))))) with
| Fail __error -> Fail __error
| Done v_target ->
(f_lower (v_remaining) ((ApplicationHead ((f_classify ((C.f_kind_of (v_target)))), v_target, (Postfix.f_arguments (v_parts)), (C.f_offset_of (v_node))))) (v_context))))
| (ApplicationHead (RecordNode, v_node, v_arguments, v_offset)) ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(match (C.f_one ((C.f_field_values (v_node) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (C.f_one ((C.f_field_values (v_node) (s_69)))) with
| Fail __error -> Fail __error
| Done v_fields ->
(f_lower (v_remaining) ((RecordApplication ((f_template_reference ((f_lookup_local (v_locals) ((C.f_name_of (v_name))))) ((f_lookup_global (v_globals) ((C.f_name_of (v_name)))))), v_name, v_fields, v_arguments, v_offset, v_node))) (v_context)))))
| (RecordApplication ((Some (v_operation)), v_head, v_fields, v_arguments, v_offset, v_node)) ->
(match (f_typed_operation_value (v_operation) ((v_fields :: v_arguments)) (v_remaining) (v_context) (v_head)) with
| Fail __error -> Fail __error
| Done v_typed ->
(f_lower (v_remaining) ((f_typed_call_work (v_typed) (v_offset))) (v_context)))
| (RecordApplication (None, v_head, v_fields, v_arguments, v_offset, v_node)) ->
(match (f_record_target (v_context) (v_head)) with
| Fail __error -> Fail __error
| Done v_target ->
(match (f_lower (v_remaining) ((f_record_elements (v_target) (v_fields) (v_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_lower (v_remaining) ((Arguments (v_value, v_arguments, v_offset))) (v_context))))
| (ApplicationHead (Intrinsic, v_head, v_arguments, v_offset)) ->
(match (f_intrinsic ((C.f_text_of (v_head))) (v_head)) with
| Fail __error -> Fail __error
| Done v_primitive ->
(f_lower (v_remaining) ((PrimitiveCall (v_primitive, v_head, v_arguments, v_offset))) (v_context)))
| (PrimitiveCall (AssociatedPrimitive, v_head, (v_member :: (v_left :: (v_right :: []))), v_offset)) ->
(match (f_literal_argument (v_member)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_lower (v_remaining) ((f_visit (v_left))) (v_context)) with
| Fail __error -> Fail __error
| Done v_l ->
(match (f_lower (v_remaining) ((f_visit (v_right))) (v_context)) with
| Fail __error -> Fail __error
| Done v_r ->
(Done ((f_located (v_offset) ((M.AssociatedExpr (v_offset, M.BinaryDispatch, v_name, [], v_l, v_r)))))))))
| (PrimitiveCall (AssociatedPrimitive, v_head, v_arguments, v_offset)) ->
(Fail ((C.f_diagnostic (v_head) (s_233) (s_234))))
| (PrimitiveCall ((EffectFamilyPrimitive (v_member, 1, 1)), v_head, (v_operation :: (v_operand :: [])), v_offset)) ->
(match (f_effect_template_name (v_operation) (v_context)) with
| Fail __error -> Fail __error
| Done v_template ->
(match (f_lower (v_remaining) ((f_visit (v_operand))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_located (v_offset) ((M.AssociatedExpr (v_offset, M.BinaryDispatch, v_member, [v_template], v_value, M.UnitExpr))))))))
| (PrimitiveCall ((EffectFamilyPrimitive (v_member, 2, 2)), v_head, (v_read :: (v_write :: (v_initial :: (v_action :: [])))), v_offset)) ->
(match (f_effect_template_name (v_read) (v_context)) with
| Fail __error -> Fail __error
| Done v_reader ->
(match (f_effect_template_name (v_write) (v_context)) with
| Fail __error -> Fail __error
| Done v_writer ->
(match (f_require_family_pair (v_context) (v_reader) (v_writer) (v_head)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_lower (v_remaining) ((f_visit (v_initial))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_lower (v_remaining) ((f_visit (v_action))) (v_context)) with
| Fail __error -> Fail __error
| Done v_body ->
(Done ((f_located (v_offset) ((M.AssociatedExpr (v_offset, M.BinaryDispatch, v_member, [v_reader; v_writer], v_value, v_body)))))))))))
| (PrimitiveCall ((EffectFamilyPrimitive (v_member, 1, 3)), v_head, (v_operation :: (v_witness :: (v_implementation :: (v_action :: [])))), v_offset)) ->
(match (f_effect_template_name (v_operation) (v_context)) with
| Fail __error -> Fail __error
| Done v_template ->
(match (f_lower (v_remaining) ((f_visit (v_witness))) (v_context)) with
| Fail __error -> Fail __error
| Done v_subject ->
(match (f_lower (v_remaining) ((f_visit (v_implementation))) (v_context)) with
| Fail __error -> Fail __error
| Done v_provider ->
(match (f_lower (v_remaining) ((f_visit (v_action))) (v_context)) with
| Fail __error -> Fail __error
| Done v_body ->
(Done ((f_located (v_offset) ((M.AssociatedExpr (v_offset, M.BinaryDispatch, v_member, [v_template], v_subject, (M.ProductExpr ([v_provider; v_body]))))))))))))
| (PrimitiveCall ((EffectFamilyPrimitive (v_member, v_templates, v_operands)), v_head, v_arguments, v_offset)) ->
(Fail ((C.f_diagnostic (v_head) (s_233) ((Base.string_append v_member (Base.string_append s_235 (Base.string_append (Base.nat_show ((Base.nat_add (v_templates) (v_operands)))) s_236)))))))
| (PrimitiveCall ((DeferredPrimitive (v_member, 1)), v_head, (v_left :: []), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_left))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_located (v_offset) ((M.AssociatedExpr (v_offset, M.BinaryDispatch, v_member, [], v_value, M.UnitExpr)))))))
| (PrimitiveCall ((DeferredPrimitive (v_member, 2)), v_head, (v_left :: (v_right :: [])), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_left))) (v_context)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_lower (v_remaining) ((f_visit (v_right))) (v_context)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_located (v_offset) ((M.AssociatedExpr (v_offset, M.BinaryDispatch, v_member, [], v_a, v_b))))))))
| (PrimitiveCall ((DeferredPrimitive (v_member, 3)), v_head, (v_witness :: (v_implementation :: (v_action :: []))), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_witness))) (v_context)) with
| Fail __error -> Fail __error
| Done v_w ->
(match (f_lower (v_remaining) ((f_visit (v_implementation))) (v_context)) with
| Fail __error -> Fail __error
| Done v_i ->
(match (f_lower (v_remaining) ((f_visit (v_action))) (v_context)) with
| Fail __error -> Fail __error
| Done v_a ->
(Done ((f_located (v_offset) ((M.AssociatedExpr (v_offset, M.BinaryDispatch, v_member, [], v_w, (M.ProductExpr ([v_i; v_a])))))))))))
| (PrimitiveCall ((DeferredPrimitive (v_member, v_arity)), v_head, v_arguments, v_offset)) ->
(Fail ((C.f_diagnostic (v_head) (s_233) ((Base.string_append v_member (Base.string_append s_235 (Base.string_append (Base.nat_show (v_arity)) s_236)))))))
| (PrimitiveCall ((ScalarPrimitive (v_operation)), v_head, (v_left :: (v_right :: [])), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_left))) (v_context)) with
| Fail __error -> Fail __error
| Done v_l ->
(match (f_lower (v_remaining) ((f_visit (v_right))) (v_context)) with
| Fail __error -> Fail __error
| Done v_r ->
(Done ((f_located (v_offset) ((M.ScalarExpr (v_operation, v_l, v_r))))))))
| (PrimitiveCall ((ScalarPrimitive (v_operator)), v_head, v_arguments, v_offset)) ->
(Fail ((C.f_diagnostic (v_head) (s_233) (s_237))))
| (PrimitiveCall ((UnaryPrimitive (v_operator)), v_head, (v_argument :: []), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_argument))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_located (v_offset) ((M.UnaryExpr (v_operator, v_value)))))))
| (PrimitiveCall ((UnaryPrimitive (v_operator)), v_head, v_arguments, v_offset)) ->
(Fail ((C.f_diagnostic (v_head) (s_233) (s_238))))
| (PrimitiveCall (ProjectPrimitive, v_head, (v_argument :: (v_index_node :: [])), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_argument))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_projection_index_children ((C.f_children_of (v_index_node))) (v_index_node)) with
| Fail __error -> Fail __error
| Done v_index ->
(Done ((f_located (v_offset) ((M.ProjectExpr (v_value, v_index))))))))
| (PrimitiveCall (ArrayGeneratePrimitive, v_head, (v_count_node :: (v_generator_node :: [])), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_count_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_count ->
(match (f_lower (v_remaining) ((f_visit (v_generator_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_generator ->
(Done ((f_located (v_offset) ((M.ArrayGenerateExpr (v_count, v_generator))))))))
| (PrimitiveCall (ArrayFillPrimitive, v_head, (v_count_node :: (v_value_node :: [])), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_count_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_count ->
(match (f_lower (v_remaining) ((f_visit (v_value_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_located (v_offset) ((M.ArrayFillExpr (v_count, v_value))))))))
| (PrimitiveCall (ArrayGetPrimitive, v_head, (v_array_node :: (v_index_node :: [])), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_array_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_array ->
(match (f_lower (v_remaining) ((f_visit (v_index_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_index ->
(Done ((f_located (v_offset) ((M.ArrayGetExpr (v_array, v_index))))))))
| (PrimitiveCall (ArraySetPrimitive, v_head, (v_array_node :: (v_index_node :: (v_value_node :: []))), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_array_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_array ->
(match (f_lower (v_remaining) ((f_visit (v_index_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_index ->
(match (f_lower (v_remaining) ((f_visit (v_value_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_located (v_offset) ((M.ArraySetExpr (v_array, v_index, v_value)))))))))
| (PrimitiveCall (ArrayLengthPrimitive, v_head, (v_array_node :: []), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_array_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_array ->
(Done ((f_located (v_offset) ((M.ArrayLengthExpr (v_array)))))))
| (PrimitiveCall (StateProviderPrimitive, v_head, (v_read :: (v_write :: (v_initial :: []))), v_offset)) ->
(match (f_require_unsealed_operation ((f_foreign_argument (v_read))) (v_read)) with
| Fail __error -> Fail __error
| Done v_valid_read ->
(match (f_require_unsealed_operation ((f_foreign_argument (v_write))) (v_write)) with
| Fail __error -> Fail __error
| Done v_valid_write ->
(match (f_lower (v_remaining) ((f_visit (v_read))) (v_context)) with
| Fail __error -> Fail __error
| Done v_read_value ->
(match (f_lower (v_remaining) ((f_visit (v_write))) (v_context)) with
| Fail __error -> Fail __error
| Done v_write_value ->
(match (f_operation_reference (v_read_value) (v_read)) with
| Fail __error -> Fail __error
| Done v_reader ->
(match (f_operation_reference (v_write_value) (v_write)) with
| Fail __error -> Fail __error
| Done v_writer ->
(match (f_lower (v_remaining) ((f_visit (v_initial))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_located (v_offset) ((f_wrap_operation_target (v_reader) ((f_wrap_operation_target (v_writer) ((M.StateProviderExpr ((f_operation_target_identity (v_reader)), (f_operation_target_identity (v_writer)), v_value)))))))))))))))))
| (PrimitiveCall (ProviderPrimitive, v_head, (v_operation :: (v_implementation :: [])), v_offset)) ->
(match (f_require_unsealed_operation ((f_foreign_argument (v_operation))) (v_operation)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_lower (v_remaining) ((f_visit (v_operation))) (v_context)) with
| Fail __error -> Fail __error
| Done v_operation_value ->
(match (f_operation_reference (v_operation_value) (v_operation)) with
| Fail __error -> Fail __error
| Done v_target ->
(match (f_lower (v_remaining) ((f_visit (v_implementation))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_located (v_offset) ((f_wrap_operation_target (v_target) ((M.ProviderExpr ((f_operation_target_identity (v_target)), v_value))))))))))))
| (PrimitiveCall (OperationDescriptorPrimitive, v_head, (v_operation :: []), v_offset)) ->
(f_lower (v_remaining) ((DescriptorOperation ((f_foreign_argument (v_operation)), v_operation, v_offset))) (v_context))
| (DescriptorOperation (true, v_operation, v_offset)) ->
(Done ((f_located (v_offset) ((M.OperationDescriptorExpr ((M.f_foreign_identity ())))))))
| (DescriptorOperation (false, v_operation, v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_operation))) (v_context)) with
| Fail __error -> Fail __error
| Done v_operation_value ->
(match (f_operation_reference (v_operation_value) (v_operation)) with
| Fail __error -> Fail __error
| Done v_target ->
(Done ((f_located (v_offset) ((f_wrap_operation_target (v_target) ((M.OperationDescriptorExpr ((f_operation_target_identity (v_target))))))))))))
| (PrimitiveCall (FunctionEffectsPrimitive, v_head, (v_target :: []), v_offset)) ->
(match (f_function_name (v_target) (v_context)) with
| Fail __error -> Fail __error
| Done v_callee ->
(Done ((f_located (v_offset) ((M.FunctionEffectsExpr (v_callee)))))))
| (PrimitiveCall (EffectHasPrimitive, v_head, (v_set :: (v_operation :: [])), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_set))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_lower (v_remaining) ((DescriptorArgument ((f_foreign_argument (v_operation)), v_operation))) (v_context)) with
| Fail __error -> Fail __error
| Done v_target ->
(Done ((f_located (v_offset) ((M.EffectHasExpr (v_value, v_target))))))))
| (DescriptorArgument (true, v_node)) ->
(Done ((f_located ((C.f_offset_of (v_node))) ((M.OperationDescriptorExpr ((M.f_foreign_identity ())))))))
| (DescriptorArgument (false, v_node)) ->
(match (f_lower (v_remaining) ((f_visit (v_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_target ->
(Done ((f_descriptor_argument (v_remaining) (v_target)))))
| (PrimitiveCall (EffectCountPrimitive, v_head, (v_set :: []), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_set))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_located (v_offset) ((M.EffectCountExpr (v_value)))))))
| (PrimitiveCall (EffectSamePrimitive, v_head, (v_left :: (v_right :: [])), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_left))) (v_context)) with
| Fail __error -> Fail __error
| Done v_l ->
(match (f_lower (v_remaining) ((f_visit (v_right))) (v_context)) with
| Fail __error -> Fail __error
| Done v_r ->
(Done ((f_located (v_offset) ((M.EffectSameExpr (v_l, v_r))))))))
| (PrimitiveCall (PanicPrimitive, v_head, (v_argument :: []), v_offset)) ->
(match (f_literal_argument (v_argument)) with
| Fail __error -> Fail __error
| Done v_message ->
(Done ((f_located (v_offset) ((M.PanicExpr (v_message)))))))
| (PrimitiveCall (PanicPrimitive, v_head, v_arguments, v_offset)) ->
(Fail ((C.f_diagnostic (v_head) (s_233) (s_239))))
| (PrimitiveCall (v_primitive, v_head, v_arguments, v_offset)) ->
(Fail ((C.f_diagnostic (v_head) (s_233) ((Base.string_append s_240 (C.f_text_of (v_head)))))))
| (ApplicationHead (Name, v_head, v_arguments, v_offset)) ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(f_lower (v_remaining) ((ApplicationTemplate ((f_template_reference ((f_lookup_local (v_locals) ((C.f_name_of (v_head))))) ((f_lookup_global (v_globals) ((C.f_name_of (v_head)))))), v_head, v_arguments, v_offset))) (v_context)))
| (ApplicationTemplate ((Some (v_operation)), v_head, v_arguments, v_offset)) ->
(match (f_typed_operation_value (v_operation) (v_arguments) (v_remaining) (v_context) (v_head)) with
| Fail __error -> Fail __error
| Done v_typed ->
(f_lower (v_remaining) ((f_typed_call_work (v_typed) (v_offset))) (v_context)))
| (ApplicationTemplate (None, v_head, v_arguments, v_offset)) ->
(match (f_resolve (v_context) (v_head)) with
| Fail __error -> Fail __error
| Done v_callee ->
(f_lower (v_remaining) ((Arguments (v_callee, v_arguments, v_offset))) (v_context)))
| (ApplicationHead (v_kind, v_head, v_arguments, v_offset)) ->
(match (f_grouped_operation (v_remaining) ((OperationHead (v_kind, v_head))) (v_arguments) (v_context)) with
| Fail __error -> Fail __error
| Done v_call ->
(f_lower (v_remaining) ((GroupedApplication (v_call, v_kind, v_head, v_arguments, v_offset))) (v_context)))
| (GroupedApplication ((Some (v_call)), v_kind, v_head, v_arguments, v_offset)) ->
(f_lower (v_remaining) ((f_typed_call_work (v_call) (v_offset))) (v_context))
| (GroupedApplication (None, v_kind, v_head, v_arguments, v_offset)) ->
(match (f_lower (v_remaining) ((Expression (v_kind, v_head))) (v_context)) with
| Fail __error -> Fail __error
| Done v_callee ->
(f_lower (v_remaining) ((Arguments (v_callee, v_arguments, v_offset))) (v_context)))
| (Arguments (v_callee, [], v_offset)) ->
(Done ((f_located (v_offset) (v_callee))))
| (Arguments (v_callee, (v_head :: v_rest), v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_head))) (v_context)) with
| Fail __error -> Fail __error
| Done v_argument ->
(f_lower (v_remaining) ((Arguments ((f_instantiate_at ((C.f_offset_of (v_head))) (1) ((O.f_invoke (v_callee) (v_argument)))), v_rest, v_offset))) (v_context)))
| (Expression (InfixNode, v_node)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_66)))) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_lower (v_remaining) ((f_visit (v_first))) (v_context)) with
| Fail __error -> Fail __error
| Done v_head ->
(f_lower (v_remaining) ((InfixTails (v_head, (C.f_field_values (v_node) (s_71)), []))) (v_context))))
| (InfixTails (v_head, [], v_tails)) ->
(O.f_resolve ((Base.nat_mul (v_fuel) (4))) ((O.Read ((Base.list_reverse (v_tails))))) ([v_head]) ([]))
| (InfixTails (v_head, (v_node :: v_rest), v_tails)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_72)))) with
| Fail __error -> Fail __error
| Done v_op_node ->
(match (f_source_operator ((f_operator_kind (v_op_node))) (v_op_node) (v_context)) with
| Fail __error -> Fail __error
| Done v_op ->
(match (C.f_one ((C.f_field_values (v_node) (s_241)))) with
| Fail __error -> Fail __error
| Done v_right_node ->
(match (f_lower (v_remaining) ((f_visit (v_right_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_right ->
(f_lower (v_remaining) ((InfixTails (v_head, v_rest, ((O.Tail (v_op, v_right)) :: v_tails)))) (v_context))))))
| (Expression (LambdaNode, v_node)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_242)))) with
| Fail __error -> Fail __error
| Done v_param_node ->
(match (f_lower_parameter (v_param_node) (v_remaining) (v_context)) with
| Fail __error -> Fail __error
| Done v_param ->
(match (f_source_annotation ((C.f_field_values (v_node) (s_38))) (v_remaining) (v_context)) with
| Fail __error -> Fail __error
| Done v_result ->
(match (C.f_one ((C.f_field_values (v_node) (s_224)))) with
| Fail __error -> Fail __error
| Done v_body_node ->
(match (f_lower (v_remaining) ((f_visit (v_body_node))) ((f_with_label ((f_bind_parameter (v_context) (v_param))) (None)))) with
| Fail __error -> Fail __error
| Done v_body ->
(Done ((f_located ((C.f_offset_of (v_node))) ((f_lambda ((C.f_offset_of (v_node))) (v_param) (v_result) (v_body)))))))))))
| (Expression (CaseNode, v_node)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_224)))) with
| Fail __error -> Fail __error
| Done v_suite ->
(match (f_lower (v_remaining) ((CaseValues ((C.f_field_values (v_node) (s_243)), [], (C.f_field_values (v_suite) (s_244))))) (v_context)) with
| Fail __error -> Fail __error
| Done v_result ->
(Done ((f_located ((C.f_offset_of (v_node))) (v_result))))))
| (CaseValues ([], v_reversed, v_arms)) ->
(f_lower (v_remaining) ((Arms ((Base.list_reverse (v_reversed)), v_arms, []))) (v_context))
| (CaseValues ((v_head :: v_tail), v_reversed, v_arms)) ->
(match (f_lower (v_remaining) ((f_visit (v_head))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_lower (v_remaining) ((CaseValues (v_tail, (v_value :: v_reversed), v_arms))) (v_context)))
| (Arms (v_values, [], v_arms)) ->
(Done ((M.MatchExpr (v_values, (Base.list_reverse (v_arms))))))
| (Arms (v_values, (v_node :: v_rest), v_arms)) ->
(match (f_lower_pattern_row ((C.f_field_values (v_node) (s_245))) (v_remaining) (v_context)) with
| Fail __error -> Fail __error
| Done v_row ->
(match (C.f_one ((C.f_field_values (v_node) (s_224)))) with
| Fail __error -> Fail __error
| Done v_body_node ->
(match (f_lower (v_remaining) ((f_visit (v_body_node))) ((f_row_scope (v_context) (v_row)))) with
| Fail __error -> Fail __error
| Done v_body ->
(f_lower (v_remaining) ((Arms (v_values, v_rest, ((M.MatchArm ((f_row_patterns (v_row)), v_body)) :: v_arms)))) (v_context)))))
| (Expression (Block, v_node)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_224)))) with
| Fail __error -> Fail __error
| Done v_suite ->
(match (f_lower (v_remaining) ((Statements ((f_statement_nodes (v_suite)), []))) ((f_with_label (v_context) ((Some ((C.f_offset_of (v_node)))))))) with
| Fail __error -> Fail __error
| Done v_body ->
(f_lower (v_remaining) ((ResolvedBlock ((C.f_field_values (v_node) (s_246)), v_body, (C.f_offset_of (v_node))))) (v_context))))
| (ResolvedBlock ([], v_body, v_offset)) ->
(Done ((f_located (v_offset) ((M.BlockExpr (v_offset, v_body))))))
| (ResolvedBlock ((v_provider_node :: []), v_body, v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_provider_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_provider ->
(Done ((f_located (v_offset) ((M.HandleExpr (v_provider, (M.BlockExpr (v_offset, v_body)))))))))
| (ResolvedBlock (v_nodes, v_body, v_offset)) ->
(Fail ((M.Diagnostic (s_47, s_82, s_247))))
| (Expression (v_kind, v_node)) ->
(Fail ((C.f_diagnostic (v_node) (s_248) (s_249))))
| (Statements ([], v_carried)) ->
(Done ((f_loop_value ((f_local_values (v_carried))))))
| (Statements ((v_statement :: v_tail), v_carried)) ->
(match (C.f_one ((C.f_field_values (v_statement) (s_65)))) with
| Fail __error -> Fail __error
| Done v_node ->
(f_lower (v_remaining) ((Statement ((f_classify ((C.f_kind_of (v_node)))), v_node, v_tail, v_carried))) (v_context)))
| (Statement (Binding, v_node, v_tail, v_carried)) ->
(let v_scope = (Base.string_append s_251 (Base.nat_show ((C.f_offset_of (v_node))))) in
(match (f_annotation_scope (v_node) (v_context) (v_scope)) with
| Fail __error -> Fail __error
| Done v_annotated ->
(match (C.f_one ((C.f_field_values (v_node) (s_31)))) with
| Fail __error -> Fail __error
| Done v_pattern_node ->
(match (f_lower_pattern (v_remaining) ((f_classify ((C.f_kind_of (v_pattern_node))))) (v_pattern_node) (v_context)) with
| Fail __error -> Fail __error
| Done v_pat ->
(match (f_source_annotation ((C.f_field_values (v_node) (s_129))) (v_remaining) (v_annotated)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (C.f_one ((C.f_field_values (v_node) (s_65)))) with
| Fail __error -> Fail __error
| Done v_value_node ->
(match (f_lower (v_remaining) ((f_visit (v_value_node))) (v_annotated)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_where_clause (v_ty) ((C.f_field_values (v_node) (s_121))) (v_value) (v_remaining) (v_annotated) (v_scope)) with
| Fail __error -> Fail __error
| Done v_qualified ->
(match (f_else_statements ((C.f_field_values (v_node) (s_250)))) with
| Fail __error -> Fail __error
| Done v_otherwise ->
(match (f_lower (v_remaining) ((Statements (v_otherwise, []))) (v_context)) with
| Fail __error -> Fail __error
| Done v_alternative ->
(match (f_lower (v_remaining) ((Statements (v_tail, v_carried))) ((f_pattern_scope (v_context) (v_pat)))) with
| Fail __error -> Fail __error
| Done v_body ->
(let v_old_annotation = (Base.bool_pick ((C.f_present ((C.f_field_values (v_node) (s_121))))) (None) (v_ty)) in
(Done ((f_located ((C.f_offset_of (v_node))) ((f_binding ((C.f_present ((C.f_field_values (v_node) (s_250))))) ((f_pattern_of (v_pat))) ((M.SourceExpr ((C.f_offset_of (v_node)), v_old_annotation, v_qualified))) (v_alternative) (v_body) ((C.f_offset_of (v_node))))))))))))))))))))
| (Statement (ForLoop, v_node, v_tail, v_carried)) ->
(match (f_loop_pattern (v_remaining) ((C.f_field_values (v_node) (s_31))) (v_context)) with
| Fail __error -> Fail __error
| Done v_pat ->
(match (C.f_one ((C.f_field_values (v_node) (s_224)))) with
| Fail __error -> Fail __error
| Done v_suite ->
(match (f_loop_targets (v_remaining) ((LoopTargets ((f_statement_nodes (v_suite))))) (v_context) ((f_shadow_names ((f_pattern_locals (v_pat))) ((Base.set_new ())))) ((Base.set_new ()))) with
| Fail __error -> Fail __error
| Done v_targets ->
(match (Done ((f_loop_locals (v_context) (v_targets)))) with
| Fail __error -> Fail __error
| Done v_originals ->
(match (Done ((Base.string_append s_254 (Base.string_append (Base.nat_show ((C.f_offset_of (v_node)))) s_93)))) with
| Fail __error -> Fail __error
| Done v_prefix ->
(match (Done ((f_loop_versions (v_originals) (v_prefix)))) with
| Fail __error -> Fail __error
| Done v_versions ->
(match (Done ((f_bind_all (v_versions) (v_context)))) with
| Fail __error -> Fail __error
| Done v_scope ->
(match (Done ((f_loop_versions (v_originals) ((Base.string_append v_prefix s_253))))) with
| Fail __error -> Fail __error
| Done v_successors ->
(match (f_lower (v_remaining) ((Statements ((f_statement_nodes (v_suite)), v_versions))) ((f_pattern_scope (v_scope) (v_pat)))) with
| Fail __error -> Fail __error
| Done v_body ->
(match (f_lower (v_remaining) ((Statements (v_tail, (f_loop_carried (v_originals) (v_successors) (v_carried))))) ((f_bind_all (v_successors) (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(match (Done ((Base.nat_is_eq ((Base.list_length (v_versions))) (1)))) with
| Fail __error -> Fail __error
| Done v_single ->
(match (f_lower (v_remaining) ((ForStart ((M.f_name_equal ((C.f_kind_of (v_node))) (s_16)), v_node, (f_pattern_of (v_pat)), (f_loop_value ((f_local_values (v_originals)))), (f_loop_bindings (v_versions) ((Base.string_append v_prefix s_252)) (0) (v_single) (v_body)), v_prefix))) (v_context)) with
| Fail __error -> Fail __error
| Done v_loop ->
(Done ((f_located ((C.f_offset_of (v_node))) ((M.UseExpr ((Base.string_append v_prefix s_38), v_loop, (f_loop_bindings (v_successors) ((Base.string_append v_prefix s_38)) (0) (v_single) (v_next))))))))))))))))))))
| (ForStart (true, v_node, v_pattern, v_initial, v_body, v_prefix)) ->
(Done ((M.ForeverExpr ((Base.string_append v_prefix s_252), v_initial, v_body))))
| (ForStart (false, v_node, v_pattern, v_initial, v_body, v_prefix)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_256)))) with
| Fail __error -> Fail __error
| Done v_start_node ->
(match (f_lower (v_remaining) ((f_visit (v_start_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_start ->
(f_lower (v_remaining) ((ForRange ((C.f_field_values (v_node) (s_255)), v_pattern, v_start, v_initial, v_body, v_prefix, (C.f_offset_of (v_node))))) (v_context))))
| (ForRange ([], v_pattern, v_array, v_initial, v_body, v_prefix, v_offset)) ->
(Done ((M.UseExpr ((Base.string_append v_prefix s_7), v_array, (M.ForExpr ((Base.string_append v_prefix s_232), (M.U32Expr ((Base.W32 0x0))), (M.ArrayLengthExpr ((M.LocalExpr ((Base.string_append v_prefix s_7))))), (Base.string_append v_prefix s_252), v_initial, (f_plain_binding (v_pattern) ((M.ArrayGetExpr ((M.LocalExpr ((Base.string_append v_prefix s_7))), (M.LocalExpr ((Base.string_append v_prefix s_232)))))) (v_body) (v_offset))))))))
| (ForRange ((v_end_node :: []), v_pattern, v_start, v_initial, v_body, v_prefix, v_offset)) ->
(match (f_lower (v_remaining) ((f_visit (v_end_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_end ->
(Done ((M.ForExpr ((Base.string_append v_prefix s_232), v_start, v_end, (Base.string_append v_prefix s_252), v_initial, (f_plain_binding (v_pattern) ((M.LocalExpr ((Base.string_append v_prefix s_232)))) (v_body) (v_offset)))))))
| (ForRange (v_nodes, v_pattern, v_start, v_initial, v_body, v_prefix, v_offset)) ->
(Fail ((M.Diagnostic (s_47, s_217, s_257))))
| (Statement (Rebinding, v_node, v_tail, v_carried)) ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(match (C.f_one ((C.f_field_values (v_node) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_rebinding_scope ((f_lookup_local (v_locals) ((C.f_text_of (v_name))))) (v_context) (v_name)) with
| Fail __error -> Fail __error
| Done v_scope ->
(match (C.f_one ((C.f_field_values (v_node) (s_65)))) with
| Fail __error -> Fail __error
| Done v_value_node ->
(match (f_self_value (v_scope)) with
| Fail __error -> Fail __error
| Done v_receiver ->
(match (f_lower (v_remaining) ((UpdatePath (v_receiver, (C.f_field_values (v_node) (s_258)), v_value_node, (C.f_offset_of (v_node))))) (v_scope)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_lower (v_remaining) ((Statements (v_tail, (f_successor_carried (v_carried) ((f_lookup_local (v_locals) ((C.f_text_of (v_name))))) ((f_unique_name (v_name))))))) ((f_bind (v_context) ((Local ((C.f_text_of (v_name)), (f_unique_name (v_name)))))))) with
| Fail __error -> Fail __error
| Done v_body ->
(Done ((f_located ((C.f_offset_of (v_node))) ((M.LetExpr ((f_unique_name (v_name)), v_value, v_body)))))))))))))
| (UpdatePath ((M.LocalExpr (v_core)), [], v_value_node, v_offset)) ->
(f_lower (v_remaining) ((f_visit (v_value_node))) ((f_bind (v_context) ((Local (s_88, v_core))))))
| (UpdatePath (v_receiver, [], v_value_node, v_offset)) ->
(let v_name = (Base.string_append s_259 (Base.nat_show (v_offset))) in
(match (f_lower (v_remaining) ((f_visit (v_value_node))) ((f_bind (v_context) ((Local (s_88, v_name)))))) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_terminal_update_value (v_receiver) (v_name) (v_value))))))
| (UpdatePath (v_receiver, (v_node :: v_tail), v_value, v_offset)) ->
(f_lower (v_remaining) ((UpdateSelector ((C.f_kind_of (v_node)), v_receiver, v_node, v_tail, v_value, v_offset))) (v_context))
| (UpdateSelector ((SCon (Chr (Base.W32 0x6d), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x6d), (SCon (Chr (Base.W32 0x62), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x72), (SCon (Chr (Base.W32 0x5f), (SCon (Chr (Base.W32 0x61), (SCon (Chr (Base.W32 0x63), (SCon (Chr (Base.W32 0x63), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x73), (SCon (Chr (Base.W32 0x73), SNil)))))))))))))))))))))))))), v_receiver, v_node, v_tail, v_value_node, v_offset)) ->
(let v_parent = (Base.string_append s_260 (Base.nat_show ((C.f_offset_of (v_node))))) in
(match (C.f_one ((C.f_field_values (v_node) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_lower (v_remaining) ((UpdatePath ((M.AssociatedExpr ((C.f_offset_of (v_name)), M.MemberDispatch, (C.f_text_of (v_name)), [], (M.LocalExpr (v_parent)), M.UnitExpr)), v_tail, v_value_node, v_offset))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((M.UseExpr (v_parent, v_receiver, (f_located ((C.f_offset_of (v_node))) ((M.AssociatedExpr ((C.f_offset_of (v_node)), M.FieldUpdateDispatch, (C.f_text_of (v_name)), [], (M.LocalExpr (v_parent)), v_value)))))))))))
| (UpdateSelector ((SCon (Chr (Base.W32 0x69), (SCon (Chr (Base.W32 0x6e), (SCon (Chr (Base.W32 0x64), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x78), (SCon (Chr (Base.W32 0x5f), (SCon (Chr (Base.W32 0x61), (SCon (Chr (Base.W32 0x63), (SCon (Chr (Base.W32 0x63), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x73), (SCon (Chr (Base.W32 0x73), SNil)))))))))))))))))))))))), v_receiver, v_node, v_tail, v_value_node, v_offset)) ->
(let v_parent = (Base.string_append s_260 (Base.nat_show ((C.f_offset_of (v_node))))) in
(let v_index_name = (Base.string_append s_261 (Base.nat_show ((C.f_offset_of (v_node))))) in
(match (C.f_one ((C.f_field_values (v_node) (s_232)))) with
| Fail __error -> Fail __error
| Done v_index_node ->
(match (f_lower (v_remaining) ((f_visit (v_index_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_index ->
(match (f_lower (v_remaining) ((UpdatePath ((M.ArrayGetExpr ((M.LocalExpr (v_parent)), (M.LocalExpr (v_index_name)))), v_tail, v_value_node, v_offset))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((M.UseExpr (v_parent, v_receiver, (M.UseExpr (v_index_name, v_index, (f_located ((C.f_offset_of (v_node))) ((M.ArraySetExpr ((M.LocalExpr (v_parent)), (M.LocalExpr (v_index_name)), v_value)))))))))))))))
| (UpdateSelector (v_kind, v_receiver, v_node, v_tail, v_value, v_offset)) ->
(Fail ((C.f_diagnostic (v_node) (s_47) (s_262))))
| (Statement (EffectBinding, v_node, v_tail, v_carried)) ->
(match (f_effect_target ((C.f_field_values (v_node) (s_70))) ((C.f_offset_of (v_node)))) with
| Fail __error -> Fail __error
| Done v_target ->
(match (f_source_annotation ((C.f_field_values (v_node) (s_129))) (v_remaining) (v_context)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (C.f_one ((C.f_field_values (v_node) (s_65)))) with
| Fail __error -> Fail __error
| Done v_value_node ->
(match (f_lower (v_remaining) ((f_visit (v_value_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_lower (v_remaining) ((Statements (v_tail, v_carried))) ((f_bind (v_context) (v_target)))) with
| Fail __error -> Fail __error
| Done v_body ->
(Done ((f_located ((C.f_offset_of (v_node))) ((f_effect_binding (v_target) ((M.SourceExpr ((C.f_offset_of (v_node)), v_ty, v_value))) (v_body)))))))))))
| (Statement (Return, v_node, v_tail, v_carried)) ->
(match (f_reachable (v_tail)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_require_plain_return ((C.f_field_values (v_node) (s_263)))) with
| Fail __error -> Fail __error
| Done v_plain ->
(match (C.f_one ((C.f_field_values (v_node) (s_65)))) with
| Fail __error -> Fail __error
| Done v_value_node ->
(match (f_lower (v_remaining) ((f_visit (v_value_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_returning (v_context) (v_value) (v_node)) with
| Fail __error -> Fail __error
| Done v_result ->
(Done ((f_located ((C.f_offset_of (v_node))) (v_result)))))))))
| (Statement (Conditional, v_node, v_tail, v_carried)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_265)))) with
| Fail __error -> Fail __error
| Done v_test ->
(match (C.f_one ((C.f_field_values (v_node) (s_264)))) with
| Fail __error -> Fail __error
| Done v_yes ->
(match (f_else_statements ((C.f_field_values (v_node) (s_250)))) with
| Fail __error -> Fail __error
| Done v_no ->
(match (f_lower (v_remaining) ((f_visit (v_test))) (v_context)) with
| Fail __error -> Fail __error
| Done v_condition ->
(match (f_lower (v_remaining) ((Statements ((f_statement_nodes (v_yes)), []))) (v_context)) with
| Fail __error -> Fail __error
| Done v_consequent ->
(match (f_lower (v_remaining) ((Statements (v_no, []))) (v_context)) with
| Fail __error -> Fail __error
| Done v_alternative ->
(match (f_lower (v_remaining) ((Statements (v_tail, v_carried))) (v_context)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((M.SequenceExpr ((f_located ((C.f_offset_of (v_node))) ((M.IfExpr (v_condition, v_consequent, v_alternative)))), v_next)))))))))))
| (Statement (PatternConditional, v_node, v_tail, v_carried)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_31)))) with
| Fail __error -> Fail __error
| Done v_pattern_node ->
(match (f_lower_pattern (v_remaining) ((f_classify ((C.f_kind_of (v_pattern_node))))) (v_pattern_node) (v_context)) with
| Fail __error -> Fail __error
| Done v_pat ->
(match (C.f_one ((C.f_field_values (v_node) (s_65)))) with
| Fail __error -> Fail __error
| Done v_value_node ->
(match (C.f_one ((C.f_field_values (v_node) (s_264)))) with
| Fail __error -> Fail __error
| Done v_yes ->
(match (f_else_statements ((C.f_field_values (v_node) (s_250)))) with
| Fail __error -> Fail __error
| Done v_no ->
(match (f_lower (v_remaining) ((f_visit (v_value_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_lower (v_remaining) ((Statements ((f_statement_nodes (v_yes)), []))) ((f_pattern_scope (v_context) (v_pat)))) with
| Fail __error -> Fail __error
| Done v_consequent ->
(match (f_lower (v_remaining) ((Statements (v_no, []))) (v_context)) with
| Fail __error -> Fail __error
| Done v_alternative ->
(match (f_lower (v_remaining) ((Statements (v_tail, v_carried))) (v_context)) with
| Fail __error -> Fail __error
| Done v_next ->
(match (Done ((Base.string_append s_266 (Base.nat_show ((C.f_offset_of (v_node))))))) with
| Fail __error -> Fail __error
| Done v_temporary ->
(Done ((M.SequenceExpr ((f_located ((C.f_offset_of (v_node))) ((M.LetExpr (v_temporary, v_value, (M.MatchExpr ([(M.LocalExpr (v_temporary))], [(M.MatchArm ([(f_pattern_of (v_pat))], v_consequent)); (M.MatchArm ([M.WildcardPattern], v_alternative))])))))), v_next))))))))))))))
| (Statement (v_kind, v_node, v_tail, v_carried)) ->
(match (f_lower (v_remaining) ((Expression (v_kind, v_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_lower (v_remaining) ((Statements (v_tail, v_carried))) (v_context)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((M.SequenceExpr (v_first, v_next)))))))))
and (* lower.bend:2113 *)
f_declaration_name : C.t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_node ->
(match (C.f_one ((C.f_field_values (v_node) (s_70)))) with
| Fail __error -> Fail __error
| Done v_name ->
(Done ((Base.bool_pick ((M.f_name_equal ((C.f_kind_of (v_name))) (s_35))) ((C.f_name_of (v_name))) ((C.f_text_of (v_name)))))))
and (* lower.bend:2118 *)
f_require_fresh : (t_Global) option -> t_Context -> t_Global -> C.t_Cst -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_found v_context v_global v_node ->
(match (v_found, v_context, v_global) with
| (None, (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)), (Global (v_source, v_core, v_kind))) ->
(Done ((Context ((Base.map_set (v_globals) (v_source) ((Global (v_source, v_core, v_kind)))), v_headers, v_fixities, v_locals, v_label, v_annotation_variables))))
| (_, _, _) ->
(Fail ((C.f_diagnostic (v_node) (s_267) (s_268)))))
and (* lower.bend:2125 *)
f_add_global : t_Context -> Base.text -> Base.text -> t_GlobalKind -> C.t_Cst -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_context v_source v_core v_kind v_node ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(f_require_fresh ((f_lookup_global (v_globals) (v_source))) (v_context) ((Global (v_source, v_core, v_kind))) (v_node)))
and (* lower.bend:2129 *)
f_add_header : (T.t_Header) option -> t_Context -> T.t_Header -> C.t_Cst -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_found v_context v_header v_node ->
(match (v_found, v_context, v_header) with
| (None, (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)), (T.Header (v_source, v_identity, v_parameters))) ->
(Done ((Context (v_globals, (Base.map_set (v_headers) (v_source) ((T.Header (v_source, v_identity, v_parameters)))), v_fixities, v_locals, v_label, v_annotation_variables))))
| (_, _, _) ->
(Fail ((C.f_diagnostic (v_node) (s_269) (s_270)))))
and (* lower.bend:2138 *)
f_constructor_fields : int -> (C.t_Cst) list -> (C.t_Cst) list =
fun v_fuel v_nodes ->
(match (v_fuel, v_nodes) with
| (__nat_35, (v_node :: [])) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(Base.bool_pick ((M.f_name_equal ((C.f_kind_of (v_node))) (s_271))) ([v_node]) ((f_constructor_fields (v_rest) ((C.f_children_of (v_node)))))))
| (_, _) ->
[])
and (* lower.bend:2145 *)
f_collect_constructors : (C.t_Cst) list -> Base.text -> t_Context -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_nodes v_prefix v_context ->
(match v_nodes with
| [] ->
(Done (v_context))
| (v_node :: v_rest) ->
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_record_kind ((f_constructor_fields (65536) ((C.f_field_values (v_node) (s_199)))))) with
| Fail __error -> Fail __error
| Done v_kind ->
(match (f_add_global (v_context) (v_name) ((Base.string_append v_prefix v_name)) (v_kind) (v_node)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_collect_constructors (v_rest) (v_prefix) (v_next))))))
and (* lower.bend:2156 *)
f_effect_member_nodes : (C.t_Cst) list -> (C.t_Cst) list =
fun v_nodes ->
(match v_nodes with
| [] ->
[]
| (v_group :: []) ->
(C.f_field_values (v_group) (s_69))
| _ ->
[])
and (* lower.bend:2165 *)
f_effect_member_identities : (C.t_Cst) list -> Base.text -> Base.text -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_ =
fun v_nodes v_family v_module_name ->
(match v_nodes with
| [] ->
(Done ([]))
| (v_node :: v_rest) ->
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_effect_member_identities (v_rest) (v_family) (v_module_name)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done (((M.TypeId (v_module_name, (Base.string_append v_family (Base.string_append s_45 v_name)))) :: v_following))))))
and (* lower.bend:2175 *)
f_operation_kind : M.t_TypeId -> (A.t_Pattern) list -> t_GlobalKind =
fun v_identity v_parameters ->
(match v_parameters with
| [] ->
(OperationName (v_identity))
| _ ->
(OperationTemplateName (v_identity, v_parameters)))
and (* lower.bend:2182 *)
f_collect_effect_members : (C.t_Cst) list -> Base.text -> Base.text -> Base.text -> (A.t_Pattern) list -> t_Context -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_nodes v_family v_prefix v_module_name v_parameters v_context ->
(match v_nodes with
| [] ->
(Done (v_context))
| (v_node :: v_rest) ->
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (Done ((Base.string_append v_family (Base.string_append s_45 v_name)))) with
| Fail __error -> Fail __error
| Done v_source ->
(match (Done ((M.TypeId (v_module_name, v_source)))) with
| Fail __error -> Fail __error
| Done v_identity ->
(match (f_add_global (v_context) (v_source) ((Base.string_append v_prefix v_source)) ((f_operation_kind (v_identity) (v_parameters))) (v_node)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_collect_effect_members (v_rest) (v_family) (v_prefix) (v_module_name) (v_parameters) (v_next)))))))
and (* lower.bend:2194 *)
f_collect_effect_type_body : (C.t_Cst) list -> Base.text -> Base.text -> Base.text -> (A.t_Pattern) list -> C.t_Cst -> t_Context -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_groups v_name v_prefix v_module_name v_parameters v_node v_with_header ->
(match v_groups with
| [] ->
(f_add_global (v_with_header) (v_name) ((Base.string_append v_prefix v_name)) ((f_operation_kind ((M.TypeId (v_module_name, v_name))) (v_parameters))) (v_node))
| v_groups ->
(match (Done ((f_effect_member_nodes (v_groups)))) with
| Fail __error -> Fail __error
| Done v_members ->
(match (f_effect_member_identities (v_members) (v_name) (v_module_name)) with
| Fail __error -> Fail __error
| Done v_identities ->
(match (f_add_global (v_with_header) (v_name) ((Base.string_append v_prefix v_name)) ((EffectFamilyName (v_identities, v_parameters))) (v_node)) with
| Fail __error -> Fail __error
| Done v_with_family ->
(f_collect_effect_members (v_members) (v_name) (v_prefix) (v_module_name) (v_parameters) (v_with_family))))))
and (* lower.bend:2205 *)
f_valid_effect_name : bool -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_reserved v_node ->
(match v_reserved with
| true ->
(Fail ((C.f_diagnostic (v_node) (s_185) (s_272))))
| false ->
(Done (())))
and (* lower.bend:2212 *)
f_collect_effect_type : C.t_Cst -> Base.text -> Base.text -> t_Context -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_node v_prefix v_module_name v_context ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_valid_effect_name ((M.f_name_equal (v_name) (s_58))) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (A.f_parameters (v_node)) with
| Fail __error -> Fail __error
| Done v_parameters ->
(match (Done ((M.TypeId (v_module_name, v_name)))) with
| Fail __error -> Fail __error
| Done v_identity ->
(match (f_add_header ((T.f_lookup_header (v_headers) (v_name))) (v_context) ((T.Header (v_name, v_identity, v_parameters))) (v_node)) with
| Fail __error -> Fail __error
| Done v_with_header ->
(f_collect_effect_type_body ((C.f_field_values (v_node) (s_273))) (v_name) (v_prefix) (v_module_name) (v_parameters) (v_node) (v_with_header))))))))
and (* lower.bend:2222 *)
f_declaration_lambda_children : t_NodeKind -> C.t_Cst -> (C.t_Cst) list =
fun v_kind v_node ->
(match v_kind with
| ApplicationNode ->
(Base.bool_pick ((Base.list_is_empty ((C.f_field_values (v_node) (s_67))))) ((C.f_field_values (v_node) (s_66))) ([]))
| v_kind ->
(f_application_children (v_kind) (v_node)))
and (* lower.bend:2233 *)
f_declaration_lambda : int -> t_DeclarationInitializer -> (M.t_Diagnostic, (C.t_Cst) option) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_47, s_82, s_274))))
| (__nat_36, (InitializerNode (LambdaNode, v_node))) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(Done ((Some (v_node)))))
| (__nat_37, (InitializerNode (v_kind, v_node))) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(f_declaration_lambda (v_rest) ((InitializerChildren ((f_declaration_lambda_children (v_kind) (v_node)))))))
| (__nat_38, (InitializerChildren ((v_node :: [])))) when __nat_38 >= 1 ->
(let v_rest = (__nat_38 - 1) in
(f_declaration_lambda (v_rest) ((InitializerNode ((f_classify ((C.f_kind_of (v_node)))), v_node)))))
| (_, _) ->
(Done (None)))
and (* lower.bend:2246 *)
f_named_declaration : t_NodeKind -> C.t_Cst -> (C.t_Cst) list -> Base.text -> Base.text -> t_Context -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_kind v_node v_attributes v_prefix v_module_name v_context ->
(match v_kind with
| ValueDeclaration ->
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (C.f_one ((C.f_field_values (v_node) (s_65)))) with
| Fail __error -> Fail __error
| Done v_initializer ->
(match (f_declaration_lambda (65536) ((InitializerChildren ([v_initializer])))) with
| Fail __error -> Fail __error
| Done v_function ->
(let v_kind = (Base.bool_pick ((Base.bool_and ((Base.maybe_is_some (v_function))) ((Base.list_is_empty (v_attributes))))) (FunctionName) (ConstantName)) in
(f_add_global (v_context) (v_name) ((Base.string_append v_prefix v_name)) (v_kind) (v_node))))))
| EffectNode ->
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_valid_effect_name ((M.f_name_equal (v_name) (s_58))) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_add_global (v_context) (v_name) ((Base.string_append v_prefix v_name)) ((OperationName ((M.TypeId (v_module_name, v_name))))) (v_node))))
| EffectTypeNode ->
(f_collect_effect_type (v_node) (v_prefix) (v_module_name) (v_context))
| DataNode ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (A.f_parameters (v_node)) with
| Fail __error -> Fail __error
| Done v_parameters ->
(match (f_add_header ((T.f_lookup_header (v_headers) (v_name))) (v_context) ((T.Header (v_name, (M.TypeId (v_module_name, v_name)), v_parameters))) (v_node)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_collect_constructors ((C.f_field_values (v_node) (s_275))) (v_prefix) (v_next))))))
| _ ->
(Done (v_context)))
and (* lower.bend:2272 *)
f_collect_names : (C.t_Cst) list -> Base.text -> Base.text -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_nodes v_prefix v_module_name ->
(match v_nodes with
| [] ->
(Done ((Context (MTip, MTip, [], [], None, []))))
| (v_head :: v_tail) ->
(match (C.f_one ((C.f_field_values (v_head) (s_65)))) with
| Fail __error -> Fail __error
| Done v_node ->
(match (f_collect_names (v_tail) (v_prefix) (v_module_name)) with
| Fail __error -> Fail __error
| Done v_rest ->
(f_named_declaration ((f_classify ((C.f_kind_of (v_node))))) (v_node) ((C.f_field_values (v_head) (s_276))) (v_prefix) (v_module_name) (v_rest)))))
and (* lower.bend:2282 *)
f_combine_context : t_Context -> t_Context -> t_Context =
fun v_own v_inherited ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_own in
(let (Context (v_base_globals, v_base_headers, v_base_fixities, v_base_locals, v_base_label, v_base_annotation_variables)) = v_inherited in
(Context ((Base.map_union (v_base_globals) (v_globals)), (Base.map_union (v_base_headers) (v_headers)), (Base.list_append (v_fixities) (v_base_fixities)), v_locals, v_label, v_annotation_variables))))
and (* lower.bend:2287 *)
f_require_header_order : bool -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_seen_value v_node ->
(match v_seen_value with
| false ->
(Done (()))
| true ->
(Fail ((C.f_diagnostic (v_node) (s_277) (s_278)))))
and (* lower.bend:2294 *)
f_fixity_name : t_NodeKind -> C.t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_kind v_node ->
(match v_kind with
| SymbolicFixity ->
(match (C.f_one ((C.f_field_values (v_node) (s_279)))) with
| Fail __error -> Fail __error
| Done v_symbol ->
(Done ((C.f_text_of (v_symbol)))))
| _ ->
(match (C.f_one ((C.f_field_values (v_node) (s_280)))) with
| Fail __error -> Fail __error
| Done v_target ->
(Done ((C.f_name_of (v_target))))))
and (* lower.bend:2305 *)
f_require_fixity : (O.t_Fixity) option -> bool -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_found v_valid_precedence v_node ->
(match (v_found, v_valid_precedence) with
| (None, true) ->
(Done (()))
| (None, false) ->
(Fail ((C.f_diagnostic (v_node) (s_281) (s_282))))
| (_, _) ->
(Fail ((C.f_diagnostic (v_node) (s_283) (s_284)))))
and (* lower.bend:2314 *)
f_fixity : t_NodeKind -> C.t_Cst -> t_Context -> (O.t_Fixity) list -> (M.t_Diagnostic, (O.t_Fixity) list) Base.result_ =
fun v_kind v_node v_context v_rest ->
(match (f_fixity_name (v_kind) (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (Done ((M.f_name_equal ((C.f_kind_of (v_node))) (s_28)))) with
| Fail __error -> Fail __error
| Done v_named ->
(match (C.f_one ((C.f_field_values (v_node) (s_286)))) with
| Fail __error -> Fail __error
| Done v_precedence_node ->
(match (C.f_integer (v_precedence_node)) with
| Fail __error -> Fail __error
| Done v_precedence ->
(match (f_require_fixity ((O.f_lookup (v_rest) (v_name) (v_named))) ((Base.u32_is_le (v_precedence) ((Base.W32 0xff)))) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (C.f_one ((C.f_field_values (v_node) (s_285)))) with
| Fail __error -> Fail __error
| Done v_association_node ->
(match (C.f_one ((C.f_field_values (v_node) (s_280)))) with
| Fail __error -> Fail __error
| Done v_target_node ->
(match (f_resolve (v_context) (v_target_node)) with
| Fail __error -> Fail __error
| Done v_target ->
(Done (((O.Fixity (v_name, v_named, v_precedence, (O.f_parse_associativity ((C.f_text_of (v_association_node)))), v_target)) :: v_rest)))))))))))
and (* lower.bend:2326 *)
f_is_fixity : t_NodeKind -> bool =
fun v_kind ->
(match v_kind with
| SymbolicFixity ->
true
| NamedFixity ->
true
| _ ->
false)
and (* lower.bend:2335 *)
f_collect_header : bool -> C.t_Cst -> bool -> t_Context -> (O.t_Fixity) list -> (M.t_Diagnostic, (O.t_Fixity) list) Base.result_ =
fun v_yes v_node v_seen_value v_context v_rest ->
(match v_yes with
| false ->
(Done (v_rest))
| true ->
(match (f_require_header_order (v_seen_value) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_fixity ((f_classify ((C.f_kind_of (v_node))))) (v_node) (v_context) (v_rest))))
and (* lower.bend:2344 *)
f_collect_fixities : (C.t_Cst) list -> t_Context -> bool -> (M.t_Diagnostic, (O.t_Fixity) list) Base.result_ =
fun v_nodes v_context v_seen_value ->
(match v_nodes with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (C.f_one ((C.f_field_values (v_head) (s_65)))) with
| Fail __error -> Fail __error
| Done v_node ->
(match (Done ((f_is_fixity ((f_classify ((C.f_kind_of (v_node)))))))) with
| Fail __error -> Fail __error
| Done v_header ->
(match (f_collect_fixities (v_tail) (v_context) ((Base.bool_or (v_seen_value) ((Base.bool_not (v_header)))))) with
| Fail __error -> Fail __error
| Done v_rest ->
(f_collect_header (v_header) (v_node) (v_seen_value) (v_context) (v_rest))))))
and (* lower.bend:2355 *)
f_with_fixities : t_Context -> (O.t_Fixity) list -> t_Context =
fun v_context v_fixities ->
(let (Context (v_globals, v_headers, v_base_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(Context (v_globals, v_headers, (Base.list_append (v_fixities) (v_base_fixities)), v_locals, v_label, v_annotation_variables)))
and (* lower.bend:2359 *)
f_function_value : Base.text -> bool -> t_Parameter -> (M.t_Ty) option -> M.t_Expr -> M.t_Function =
fun v_name v_exported v_param v_result v_body ->
(let (Parameter (v_source, v_core, v_annotation)) = v_param in
(M.Function (v_name, v_exported, v_core, v_annotation, v_result, v_body)))
and (* lower.bend:2364 *)
f_lower_function : C.t_Cst -> Base.text -> bool -> int -> t_Context -> (M.t_Diagnostic, M.t_Function) Base.result_ =
fun v_node v_name v_exported v_fuel v_context ->
(match (C.f_one ((C.f_field_values (v_node) (s_242)))) with
| Fail __error -> Fail __error
| Done v_parameter_node ->
(match (f_lower_parameter (v_parameter_node) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_param ->
(match (f_source_annotation ((C.f_field_values (v_node) (s_38))) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_result ->
(match (C.f_one ((C.f_field_values (v_node) (s_224)))) with
| Fail __error -> Fail __error
| Done v_body_node ->
(match (f_lower (v_fuel) ((f_visit (v_body_node))) ((f_bind_parameter (v_context) (v_param)))) with
| Fail __error -> Fail __error
| Done v_body ->
(Done ((f_function_value (v_name) (v_exported) (v_param) (v_result) (v_body)))))))))
and (* lower.bend:2373 *)
f_tag_lowered : (M.t_Diagnostic, M.t_Expr) Base.result_ -> C.t_Cst -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_value v_tag ->
(match v_value with
| (Done (v_expression)) ->
(Done (v_expression))
| (Fail ((M.Diagnostic (v_code, v_subject, v_message)))) ->
(Fail ((C.f_diagnostic (v_tag) (v_code) (v_message)))))
and (* lower.bend:2380 *)
f_tag_body : (M.t_Diagnostic, C.t_Cst) Base.result_ -> C.t_Cst -> int -> t_Context -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_value v_tag v_fuel v_context ->
(match v_value with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done (v_expression)) ->
(f_tag_lowered ((f_lower (v_fuel) ((f_visit (v_expression))) (v_context))) (v_tag)))
and (* lower.bend:2387 *)
f_tag_expression_body : (M.t_Diagnostic, C.t_Cst) Base.result_ -> C.t_Cst -> int -> t_Context -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_value v_tag v_fuel v_context ->
(match v_value with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done (v_body)) ->
(f_tag_body ((C.f_one ((C.f_field_values (v_body) (s_65))))) (v_tag) (v_fuel) (v_context)))
and (* lower.bend:2394 *)
f_tag_expression : C.t_Cst -> int -> t_Context -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_tag v_fuel v_context ->
(f_tag_expression_body ((C.f_one ((C.f_field_values (v_tag) (s_224))))) (v_tag) (v_fuel) (v_context))
and (* lower.bend:2399 *)
f_tag_application : int -> M.t_Expr -> M.t_Expr -> M.t_Expr =
fun v_offset v_function v_value ->
(M.TagExpr (v_offset, v_function, v_value))
and (* lower.bend:2402 *)
f_apply_tags : (C.t_Cst) list -> M.t_Expr -> int -> t_Context -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_tags v_value v_fuel v_context ->
(match v_tags with
| [] ->
(Done (v_value))
| (v_tag :: v_tail) ->
(match (f_apply_tags (v_tail) (v_value) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_inner ->
(match (f_tag_expression (v_tag) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_function ->
(Done ((f_tag_application ((C.f_offset_of (v_tag))) (v_function) (v_inner)))))))
and (* lower.bend:2412 *)
f_reject_recursive_tag_found : bool -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_found v_tag ->
(match v_found with
| true ->
(Fail ((C.f_diagnostic (v_tag) (s_287) (s_288))))
| false ->
(Done (())))
and (* lower.bend:2419 *)
f_reject_recursive_tag : (C.t_Cst) list -> Base.text -> M.t_Expr -> (M.t_Diagnostic, unit) Base.result_ =
fun v_tags v_name v_value ->
(match v_tags with
| [] ->
(Done (()))
| (v_tag :: v_tail) ->
(match (D.f_references (65536) ((D.Expression (v_value)))) with
| Fail __error -> Fail __error
| Done v_refs ->
(f_reject_recursive_tag_found ((D.f_contains ((D.f_names_of (v_refs))) (v_name))) (v_tag))))
and (* lower.bend:2430 *)
f_qualified_root : bool -> bool -> int -> M.t_Expr -> M.t_Expr =
fun v_exported v_constrained v_offset v_value ->
(match (v_exported, v_constrained) with
| (true, true) ->
(f_instantiate_at (v_offset) (3) (v_value))
| (_, _) ->
v_value)
and (* lower.bend:2437 *)
f_lower_constant : C.t_Cst -> (C.t_Cst) list -> Base.text -> bool -> int -> t_Context -> (M.t_Diagnostic, M.t_Constant) Base.result_ =
fun v_node v_attributes v_name v_exported v_fuel v_base_context ->
(match (f_annotation_scope (v_node) (v_base_context) (v_name)) with
| Fail __error -> Fail __error
| Done v_context ->
(match (f_source_annotation ((C.f_field_values (v_node) (s_129))) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (C.f_one ((C.f_field_values (v_node) (s_65)))) with
| Fail __error -> Fail __error
| Done v_value_node ->
(match (f_lower (v_fuel) ((f_visit (v_value_node))) (v_context)) with
| Fail __error -> Fail __error
| Done v_initial ->
(match (f_apply_tags (v_attributes) (v_initial) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_reject_recursive_tag (v_attributes) (v_name) (v_value)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_where_clause (v_ty) ((C.f_field_values (v_node) (s_121))) (v_value) (v_fuel) (v_context) (v_name)) with
| Fail __error -> Fail __error
| Done v_qualified ->
(match (C.f_one ((C.f_field_values (v_node) (s_118)))) with
| Fail __error -> Fail __error
| Done v_keyword ->
(let v_old_annotation = (Base.bool_pick ((C.f_present ((C.f_field_values (v_node) (s_121))))) (None) (v_ty)) in
(let v_root = (f_qualified_root (v_exported) ((C.f_present ((C.f_field_values (v_node) (s_121))))) ((C.f_offset_of (v_node))) (v_qualified)) in
(Done ((M.Constant (v_name, v_exported, v_old_annotation, (Base.bool_pick ((M.f_name_equal ((C.f_text_of (v_keyword))) (s_289))) ((M.RuntimeInitExpr (v_root))) (v_root))))))))))))))))
and (* lower.bend:2451 *)
f_annotated_function : (M.t_Ty) option -> M.t_Function -> C.t_Cst -> M.t_Function =
fun v_annotation v_function v_node ->
(match (v_annotation, v_function) with
| (None, v_function) ->
v_function
| ((Some (v_ty)), (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body))) ->
(let v_offset = (C.f_offset_of (v_node)) in
(M.Function (v_name, v_exported, v_parameter, None, None, (M.ApplyExpr ((M.SourceExpr (v_offset, (Some (v_ty)), (M.LambdaExpr (v_offset, v_parameter, v_p, v_r, v_body)))), (M.LocalExpr (v_parameter))))))))
and (* lower.bend:2459 *)
f_qualified_function : (M.t_Ty) option -> M.t_Function -> C.t_Cst -> int -> t_Context -> Base.text -> (M.t_Diagnostic, M.t_Function) Base.result_ =
fun v_annotation v_function v_node v_fuel v_context v_scope ->
(match v_function with
| (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) ->
(let v_offset = (C.f_offset_of (v_node)) in
(match (f_where_clause (v_annotation) ((C.f_field_values (v_node) (s_121))) ((M.LambdaExpr (v_offset, v_parameter, v_p, v_r, v_body))) (v_fuel) (v_context) (v_scope)) with
| Fail __error -> Fail __error
| Done v_qualified ->
(Done ((M.Function (v_name, v_exported, v_parameter, None, None, (M.ApplyExpr ((f_qualified_root (v_exported) (true) (v_offset) (v_qualified)), (M.LocalExpr (v_parameter)))))))))))
and (* lower.bend:2467 *)
f_binding_function_found : bool -> (M.t_Ty) option -> M.t_Function -> C.t_Cst -> int -> t_Context -> Base.text -> (M.t_Diagnostic, M.t_Function) Base.result_ =
fun v_found v_annotation v_function v_node v_fuel v_context v_scope ->
(match v_found with
| true ->
(f_qualified_function (v_annotation) (v_function) (v_node) (v_fuel) (v_context) (v_scope))
| false ->
(Done ((f_annotated_function (v_annotation) (v_function) (v_node)))))
and (* lower.bend:2474 *)
f_binding_function : (M.t_Ty) option -> M.t_Function -> C.t_Cst -> int -> t_Context -> Base.text -> (M.t_Diagnostic, M.t_Function) Base.result_ =
fun v_annotation v_function v_node v_fuel v_context v_scope ->
(f_binding_function_found ((C.f_present ((C.f_field_values (v_node) (s_121))))) (v_annotation) (v_function) (v_node) (v_fuel) (v_context) (v_scope))
and (* lower.bend:2477 *)
f_value_function_phase : bool -> M.t_Function -> M.t_Function =
fun v_runtime v_function ->
(match (v_runtime, v_function) with
| (false, v_function) ->
v_function
| (true, (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body))) ->
(M.Function (v_name, v_exported, v_parameter, v_p, v_r, (M.RuntimeInitExpr (v_body)))))
and (* lower.bend:2484 *)
f_lower_value_function : C.t_Cst -> C.t_Cst -> Base.text -> bool -> int -> t_Context -> (M.t_Diagnostic, M.t_Function) Base.result_ =
fun v_binding v_node v_name v_exported v_fuel v_base_context ->
(match (f_annotation_scope (v_binding) (v_base_context) (v_name)) with
| Fail __error -> Fail __error
| Done v_context ->
(match (f_source_annotation ((C.f_field_values (v_binding) (s_129))) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_annotation ->
(match (f_lower_function (v_node) (v_name) (v_exported) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_function ->
(match (C.f_one ((C.f_field_values (v_binding) (s_118)))) with
| Fail __error -> Fail __error
| Done v_keyword ->
(match (f_binding_function (v_annotation) (v_function) (v_binding) (v_fuel) (v_context) (v_name)) with
| Fail __error -> Fail __error
| Done v_qualified ->
(Done ((f_value_function_phase ((M.f_name_equal ((C.f_text_of (v_keyword))) (s_289))) (v_qualified)))))))))
and (* lower.bend:2493 *)
f_require_parameter : (M.t_Ty) option -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_found v_node ->
(match v_found with
| None ->
(Done (()))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_290) (s_291)))))
and (* lower.bend:2500 *)
f_named_type_variables : (Base.text) list -> int -> C.t_Cst -> (M.t_Diagnostic, (T.t_Variable) list) Base.result_ =
fun v_names v_index v_node ->
(match v_names with
| [] ->
(Done ([]))
| (v_name :: v_tail) ->
(match (f_named_type_variables (v_tail) ((Base.nat_add 1 v_index)) (v_node)) with
| Fail __error -> Fail __error
| Done v_rest ->
(match (f_require_parameter ((T.f_lookup_variable (v_rest) (v_name))) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(Done (((T.Variable (v_name, (M.ParameterTy (v_index)), T.TypeKind)) :: v_rest))))))
and (* lower.bend:2510 *)
f_type_variables : C.t_Cst -> (M.t_Diagnostic, (T.t_Variable) list) Base.result_ =
fun v_node ->
(match (A.f_parameters (v_node)) with
| Fail __error -> Fail __error
| Done v_patterns ->
(match (A.f_binding_names (65536) (v_patterns)) with
| Fail __error -> Fail __error
| Done v_names ->
(f_named_type_variables (v_names) (0) (v_node))))
and (* lower.bend:2516 *)
f_record_annotation : (C.t_Cst) list -> C.t_Cst -> (M.t_Diagnostic, C.t_Cst) Base.result_ =
fun v_nodes v_node ->
(match v_nodes with
| [] ->
(C.f_one ((C.f_field_values (v_node) (s_70))))
| v_nodes ->
(C.f_one (v_nodes)))
and (* lower.bend:2523 *)
f_lower_record_types : (C.t_Cst) list -> (M.t_Ty) list -> int -> (T.t_Header) Base.map -> (T.t_Variable) list -> (t_Global) Base.map -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_nodes v_reversed v_fuel v_headers v_variables v_globals ->
(match v_nodes with
| [] ->
(Done ((Base.list_reverse (v_reversed))))
| (v_node :: v_rest) ->
(match (f_record_annotation ((C.f_field_values (v_node) (s_65))) (v_node)) with
| Fail __error -> Fail __error
| Done v_ty_node ->
(match (T.f_lower (f_lookup_effect) (v_fuel) ((T.f_visit (v_ty_node))) (v_headers) (v_variables) (v_globals)) with
| Fail __error -> Fail __error
| Done v_types ->
(match (T.f_one (v_types)) with
| Fail __error -> Fail __error
| Done v_ty ->
(f_lower_record_types (v_rest) ((v_ty :: v_reversed)) (v_fuel) (v_headers) (v_variables) (v_globals))))))
and (* lower.bend:2534 *)
f_record_payload_type : (M.t_Ty) list -> (M.t_Ty) option =
fun v_types ->
(match v_types with
| [] ->
None
| (v_ty :: []) ->
(Some (v_ty))
| (v_first :: (v_second :: v_rest)) ->
(Some ((M.ProductTy ((v_first :: (v_second :: v_rest)))))))
and (* lower.bend:2543 *)
f_constructor_payload : (C.t_Cst) list -> (C.t_Cst) list -> int -> (T.t_Header) Base.map -> (T.t_Variable) list -> (t_Global) Base.map -> (M.t_Diagnostic, (M.t_Ty) option) Base.result_ =
fun v_nodes v_payload v_fuel v_headers v_variables v_globals ->
(match v_nodes with
| [] ->
(T.f_annotation (f_lookup_effect) (v_payload) (v_fuel) (v_headers) (v_variables) (v_globals))
| (v_node :: []) ->
(match (f_lower_record_types ((C.f_field_values (v_node) (s_69))) ([]) (v_fuel) (v_headers) (v_variables) (v_globals)) with
| Fail __error -> Fail __error
| Done v_types ->
(Done ((f_record_payload_type (v_types)))))
| _ ->
(Fail ((M.Diagnostic (s_47, s_82, s_83)))))
and (* lower.bend:2554 *)
f_constructor_field_names : (C.t_Cst) list -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_nodes ->
(match v_nodes with
| [] ->
(Done ([]))
| (v_node :: []) ->
(f_record_field_names ((C.f_field_values (v_node) (s_69))) ((Base.set_new ())) ([]))
| _ ->
(Fail ((M.Diagnostic (s_47, s_37, s_292)))))
and (* lower.bend:2563 *)
f_lower_constructors : (C.t_Cst) list -> Base.text -> int -> (T.t_Header) Base.map -> (T.t_Variable) list -> (t_Global) Base.map -> (M.t_Diagnostic, (M.t_Constructor) list) Base.result_ =
fun v_nodes v_prefix v_fuel v_headers v_variables v_globals ->
(match v_nodes with
| [] ->
(Done ([]))
| (v_node :: v_tail) ->
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_constructor_payload ((f_constructor_fields (65536) ((C.f_field_values (v_node) (s_199))))) ((C.f_field_values (v_node) (s_199))) (v_fuel) (v_headers) (v_variables) (v_globals)) with
| Fail __error -> Fail __error
| Done v_payload ->
(match (f_constructor_field_names ((f_constructor_fields (65536) ((C.f_field_values (v_node) (s_199)))))) with
| Fail __error -> Fail __error
| Done v_fields ->
(match (f_lower_constructors (v_tail) (v_prefix) (v_fuel) (v_headers) (v_variables) (v_globals)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((M.Constructor ((Base.string_append v_prefix v_name), v_payload, v_fields)) :: v_rest))))))))
and (* lower.bend:2575 *)
f_lower_data : C.t_Cst -> Base.text -> Base.text -> Base.text -> int -> t_Context -> (M.t_Diagnostic, M.t_DataType) Base.result_ =
fun v_node v_name v_prefix v_module_name v_fuel v_context ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(match (f_type_variables (v_node)) with
| Fail __error -> Fail __error
| Done v_variables ->
(match (f_lower_constructors ((C.f_field_values (v_node) (s_275))) (v_prefix) (v_fuel) (v_headers) (v_variables) (v_globals)) with
| Fail __error -> Fail __error
| Done v_constructors ->
(Done ((M.DataType ((M.TypeId (v_module_name, v_name)), (Base.list_length (v_variables)), v_constructors)))))))
and (* lower.bend:2582 *)
f_operation_signature : (M.t_Ty) option -> M.t_TypeId -> (int) option -> C.t_Cst -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_signature v_identity v_parameters v_node ->
(match v_signature with
| (Some ((M.FunctionTy (v_parameter, v_result, (M.EffectRow ([], M.ClosedRow)))))) ->
(match v_parameters with
| None ->
(Done ((M.Operation (v_identity, v_parameter, v_result))))
| (Some (v_count)) ->
(Done ((M.OperationTemplate (v_identity, v_count, v_parameter, v_result)))))
| (Some ((M.FunctionTy (v_parameter, v_result, v_row)))) ->
(Fail ((C.f_diagnostic (v_node) (s_293) (s_294))))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_293) (s_295)))))
and (* lower.bend:2595 *)
f_lower_operation : C.t_Cst -> M.t_TypeId -> int -> t_Context -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_node v_identity v_fuel v_context ->
(match (f_source_annotation ((C.f_field_values (v_node) (s_296))) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_signature ->
(f_operation_signature (v_signature) (v_identity) (None) (v_node)))
and (* lower.bend:2600 *)
f_lower_effect_signature : C.t_Cst -> M.t_TypeId -> (T.t_Variable) list -> int -> t_Context -> (int) option -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_node v_identity v_variables v_fuel v_context v_parameters ->
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(match (T.f_annotation (f_lookup_effect) ((C.f_field_values (v_node) (s_296))) (v_fuel) (v_headers) (v_variables) (v_globals)) with
| Fail __error -> Fail __error
| Done v_signature ->
(f_operation_signature (v_signature) (v_identity) (v_parameters) (v_node))))
and (* lower.bend:2606 *)
f_lower_effect_members : (C.t_Cst) list -> Base.text -> Base.text -> (T.t_Variable) list -> int -> t_Context -> (int) option -> (M.t_Diagnostic, (M.t_Operation) list) Base.result_ =
fun v_nodes v_family v_module_name v_variables v_fuel v_context v_parameters ->
(match v_nodes with
| [] ->
(Done ([]))
| (v_node :: v_rest) ->
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_lower_effect_signature (v_node) ((M.TypeId (v_module_name, (Base.string_append v_family (Base.string_append s_45 v_name))))) (v_variables) (v_fuel) (v_context) (v_parameters)) with
| Fail __error -> Fail __error
| Done v_operation ->
(match (f_lower_effect_members (v_rest) (v_family) (v_module_name) (v_variables) (v_fuel) (v_context) (v_parameters)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((v_operation :: v_following)))))))
and (* lower.bend:2617 *)
f_lower_effect_type_members : (C.t_Cst) list -> C.t_Cst -> Base.text -> Base.text -> (T.t_Variable) list -> int -> t_Context -> (int) option -> (M.t_Diagnostic, (M.t_Operation) list) Base.result_ =
fun v_members v_node v_name v_module_name v_variables v_fuel v_context v_parameters ->
(match v_members with
| [] ->
(Fail ((C.f_diagnostic (v_node) (s_297) (s_298))))
| _ ->
(f_lower_effect_members (v_members) (v_name) (v_module_name) (v_variables) (v_fuel) (v_context) (v_parameters)))
and (* lower.bend:2624 *)
f_lower_effect_type_body : (C.t_Cst) list -> C.t_Cst -> Base.text -> Base.text -> (T.t_Variable) list -> int -> t_Context -> (int) option -> (M.t_Diagnostic, (M.t_Operation) list) Base.result_ =
fun v_groups v_node v_name v_module_name v_variables v_fuel v_context v_parameters ->
(match v_groups with
| [] ->
(match (f_lower_effect_signature (v_node) ((M.TypeId (v_module_name, v_name))) (v_variables) (v_fuel) (v_context) (v_parameters)) with
| Fail __error -> Fail __error
| Done v_operation ->
(Done ([v_operation])))
| _ ->
(f_lower_effect_type_members ((f_effect_member_nodes (v_groups))) (v_node) (v_name) (v_module_name) (v_variables) (v_fuel) (v_context) (v_parameters)))
and (* lower.bend:2633 *)
f_lower_effect_type : C.t_Cst -> Base.text -> Base.text -> int -> t_Context -> (M.t_Diagnostic, (M.t_Operation) list) Base.result_ =
fun v_node v_name v_module_name v_fuel v_context ->
(match (f_type_variables (v_node)) with
| Fail __error -> Fail __error
| Done v_variables ->
(let v_parameters = (Base.bool_pick ((C.f_present ((C.f_field_values (v_node) (s_299))))) ((Some ((Base.list_length (v_variables))))) (None)) in
(f_lower_effect_type_body ((C.f_field_values (v_node) (s_273))) (v_node) (v_name) (v_module_name) (v_variables) (v_fuel) (v_context) (v_parameters))))
and (* lower.bend:2639 *)
f_add_operation : M.t_Module -> M.t_Operation -> M.t_Module =
fun v_module v_operation ->
(let (M.Module (v_constants, v_functions, v_data_types, v_operations)) = v_module in
(M.Module (v_constants, v_functions, v_data_types, (v_operation :: v_operations))))
and (* lower.bend:2643 *)
f_add_operations : M.t_Module -> (M.t_Operation) list -> M.t_Module =
fun v_module v_incoming ->
(let (M.Module (v_constants, v_functions, v_data_types, v_operations)) = v_module in
(M.Module (v_constants, v_functions, v_data_types, (Base.list_append (v_incoming) (v_operations)))))
and (* lower.bend:2647 *)
f_add_function : M.t_Module -> M.t_Function -> M.t_Module =
fun v_module v_fn ->
(let (M.Module (v_constants, v_functions, v_data_types, v_operations)) = v_module in
(M.Module (v_constants, (v_fn :: v_functions), v_data_types, v_operations)))
and (* lower.bend:2651 *)
f_add_constant : M.t_Module -> M.t_Constant -> M.t_Module =
fun v_module v_constant ->
(let (M.Module (v_constants, v_functions, v_data_types, v_operations)) = v_module in
(M.Module ((v_constant :: v_constants), v_functions, v_data_types, v_operations)))
and (* lower.bend:2655 *)
f_add_data : M.t_Module -> M.t_DataType -> M.t_Module =
fun v_module v_ty ->
(let (M.Module (v_constants, v_functions, v_data_types, v_operations)) = v_module in
(M.Module (v_constants, v_functions, (v_ty :: v_data_types), v_operations)))
and (* lower.bend:2659 *)
f_lower_value_declaration : (C.t_Cst) option -> C.t_Cst -> (C.t_Cst) list -> Base.text -> bool -> M.t_Module -> int -> t_Context -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_function v_node v_attributes v_name v_exported v_rest v_fuel v_context ->
(match v_function with
| (Some (v_lambda)) ->
(match (f_lower_value_function (v_node) (v_lambda) (v_name) (v_exported) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_add_function (v_rest) (v_value)))))
| None ->
(match (f_lower_constant (v_node) (v_attributes) (v_name) (v_exported) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_add_constant (v_rest) (v_value))))))
and (* lower.bend:2674 *)
f_entry_modifier : bool -> bool -> C.t_Cst -> (M.t_Diagnostic, bool) Base.result_ =
fun v_entry v_entry_module v_node ->
(match (v_entry, v_entry_module) with
| (false, _) ->
(Fail ((C.f_diagnostic (v_node) (s_300) (s_301))))
| (true, true) ->
(Done (true))
| (true, false) ->
(Fail ((C.f_diagnostic (v_node) (s_302) (s_303)))))
and (* lower.bend:2683 *)
f_declaration_modifier : (C.t_Cst) list -> bool -> (M.t_Diagnostic, bool) Base.result_ =
fun v_modifiers v_entry_module ->
(match v_modifiers with
| [] ->
(Done (false))
| (v_node :: []) ->
(f_entry_modifier ((M.f_name_equal ((C.f_text_of (v_node))) (s_304))) (v_entry_module) (v_node))
| (v_node :: v_tail) ->
(Fail ((C.f_diagnostic (v_node) (s_47) (s_305)))))
and (* lower.bend:2692 *)
f_reject_attributes : (C.t_Cst) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_attributes ->
(match v_attributes with
| [] ->
(Done (()))
| (v_node :: v_tail) ->
(Fail ((C.f_diagnostic (v_node) (s_306) (s_307)))))
and (* lower.bend:2699 *)
f_declaration : t_NodeKind -> C.t_Cst -> (C.t_Cst) list -> Base.text -> Base.text -> bool -> M.t_Module -> int -> t_Context -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_kind v_node v_attributes v_prefix v_module_name v_entry_module v_rest v_fuel v_context ->
(match v_kind with
| ValueDeclaration ->
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_declaration_modifier ((C.f_field_values (v_node) (s_308))) (v_entry_module)) with
| Fail __error -> Fail __error
| Done v_entry ->
(match (C.f_one ((C.f_field_values (v_node) (s_65)))) with
| Fail __error -> Fail __error
| Done v_initializer ->
(match (f_declaration_lambda (v_fuel) ((InitializerChildren ([v_initializer])))) with
| Fail __error -> Fail __error
| Done v_function ->
(f_lower_value_declaration ((Base.bool_pick ((Base.list_is_empty (v_attributes))) (v_function) (None))) (v_node) (v_attributes) ((Base.string_append v_prefix v_name)) (v_entry) (v_rest) (v_fuel) (v_context))))))
| EffectNode ->
(match (f_reject_attributes (v_attributes)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_lower_operation (v_node) ((M.TypeId (v_module_name, v_name))) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_operation ->
(Done ((f_add_operation (v_rest) (v_operation)))))))
| EffectTypeNode ->
(match (f_reject_attributes (v_attributes)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_lower_effect_type (v_node) (v_name) (v_module_name) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_operations ->
(Done ((f_add_operations (v_rest) (v_operations)))))))
| DataNode ->
(match (f_reject_attributes (v_attributes)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_declaration_name (v_node)) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_lower_data (v_node) (v_name) (v_prefix) (v_module_name) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((f_add_data (v_rest) (v_ty)))))))
| _ ->
(match (f_reject_attributes (v_attributes)) with
| Fail __error -> Fail __error
| Done v_valid ->
(Done (v_rest))))
and (* lower.bend:2732 *)
f_lower_declarations_sequential : (C.t_Cst) list -> Base.text -> Base.text -> bool -> int -> t_Context -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_nodes v_prefix v_module_name v_entry_module v_fuel v_context ->
(match v_nodes with
| [] ->
(Done ((M.Module ([], [], [], []))))
| (v_head :: v_tail) ->
(match (C.f_one ((C.f_field_values (v_head) (s_65)))) with
| Fail __error -> Fail __error
| Done v_node ->
(match (f_lower_declarations_sequential (v_tail) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_rest ->
(f_declaration ((f_classify ((C.f_kind_of (v_node))))) (v_node) ((C.f_field_values (v_head) (s_276))) (v_prefix) (v_module_name) (v_entry_module) (v_rest) (v_fuel) (v_context)))))
and (* lower.bend:2742 *)
f_combine_modules : M.t_Module -> M.t_Module -> M.t_Module =
fun v_prelude v_module ->
(let (M.Module (v_pc, v_pf, v_pt, v_po)) = v_prelude in
(let (M.Module (v_mc, v_mf, v_mt, v_mo)) = v_module in
(M.Module ((Base.list_append (v_pc) (v_mc)), (Base.list_append (v_pf) (v_mf)), (Base.list_append (v_pt) (v_mt)), (Base.list_append (v_po) (v_mo))))))
and (* lower.bend:2757 *)
f_next_cost_node : ((C.t_Cst) list) list -> (t_CostNode) option =
fun v_pending ->
(match v_pending with
| [] ->
None
| ([] :: v_tail) ->
(f_next_cost_node (v_tail))
| ((v_head :: v_siblings) :: v_tail) ->
(Some ((CostNode (v_head, (v_siblings :: v_tail))))))
and (* lower.bend:2766 *)
f_declaration_cost_walk : int -> (t_CostNode) option -> int -> int =
fun v_fuel v_pending v_cost ->
(match (v_fuel, v_pending) with
| (0, _) ->
v_cost
| (_, None) ->
v_cost
| (__nat_39, (Some ((CostNode ((C.Cst (v_kind, v_field, v_text, v_offset, v_children)), v_tail))))) when __nat_39 >= 1 ->
(let v_rest = (__nat_39 - 1) in
(f_declaration_cost_walk (v_rest) ((f_next_cost_node ((v_children :: v_tail)))) ((Base.nat_add 1 v_cost)))))
and (* lower.bend:2775 *)
f_declaration_cost : int -> (C.t_Cst) list -> int -> int =
fun v_fuel v_pending v_cost ->
(match v_fuel with
| 0 ->
v_cost
| __nat_40 when __nat_40 >= 1 ->
(let v_rest = (__nat_40 - 1) in
(f_declaration_cost_walk ((Base.nat_add 1 v_rest)) ((f_next_cost_node ([v_pending]))) (v_cost))))
and (* lower.bend:2782 *)
f_weigh_declarations : (C.t_Cst) list -> (t_WeightedDeclaration) list -> (t_WeightedDeclaration) list =
fun v_nodes v_reversed ->
(match v_nodes with
| [] ->
(Base.list_reverse (v_reversed))
| (v_node :: v_tail) ->
(f_weigh_declarations (v_tail) (((WeightedDeclaration (v_node, (f_declaration_cost ((Base.u32_to_nat ((Base.W32 0x10000)))) ([v_node]) (0)))) :: v_reversed))))
and (* lower.bend:2789 *)
f_declaration_nodes : (t_WeightedDeclaration) list -> (C.t_Cst) list -> (C.t_Cst) list =
fun v_nodes v_reversed ->
(match v_nodes with
| [] ->
(Base.list_reverse (v_reversed))
| ((WeightedDeclaration (v_node, v_cost)) :: v_tail) ->
(f_declaration_nodes (v_tail) ((v_node :: v_reversed))))
and (* lower.bend:2796 *)
f_declaration_weight : (t_WeightedDeclaration) list -> int -> int =
fun v_nodes v_weight ->
(match v_nodes with
| [] ->
v_weight
| ((WeightedDeclaration (v_node, v_cost)) :: v_tail) ->
(f_declaration_weight (v_tail) ((Base.nat_add (v_weight) (v_cost)))))
and (* lower.bend:2803 *)
f_nearer_declaration_boundary : bool -> int -> int =
fun v_previous v_count ->
(match v_previous with
| true ->
v_count
| false ->
(Base.nat_add 1 v_count))
and (* lower.bend:2812 *)
f_declaration_boundary : (t_WeightedDeclaration) list -> int -> int -> int -> bool -> int =
fun v_nodes v_target v_weight v_count v_ready ->
(match (v_nodes, v_ready) with
| (_, true) ->
v_count
| ([], false) ->
v_count
| ((v_head :: []), false) ->
v_count
| (((WeightedDeclaration (v_node, v_cost)) :: v_tail), false) ->
(let v_next = (Base.nat_add (v_weight) (v_cost)) in
(f_declaration_boundary (v_tail) (v_target) (v_next) ((f_nearer_declaration_boundary ((Base.bool_and ((Base.nat_is_gt (v_count) (0))) ((Base.nat_is_le ((Base.nat_sub (v_target) (v_weight))) ((Base.nat_sub (v_next) (v_target))))))) (v_count))) ((Base.nat_is_ge (v_next) (v_target))))))
and (* lower.bend:2824 *)
f_weighted_declaration_batches : int -> (t_WeightedDeclaration) list -> int -> int -> bool -> t_DeclarationBatch =
fun v_depth v_nodes v_count v_weight v_small ->
(match (v_depth, v_small) with
| (__nat_41, false) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
(let v_half = (f_declaration_boundary (v_nodes) ((Base.nat_div (v_weight) (2))) (0) (0) (false)) in
(let v_remaining = (Base.nat_sub (v_count) (v_half)) in
(let v_left = (Base.list_take (v_nodes) (v_half)) in
(let v_right = (Base.list_drop (v_nodes) (v_half)) in
(let v_left_weight = (f_declaration_weight (v_left) (0)) in
(let v_right_weight = (Base.nat_sub (v_weight) (v_left_weight)) in
(DeclarationFork ((f_weighted_declaration_batches (v_rest) (v_left) (v_half) (v_left_weight) ((Base.bool_or ((Base.nat_is_le (v_half) (1))) ((Base.bool_and ((Base.nat_is_le (v_half) (4))) ((Base.nat_is_le (v_left_weight) ((Base.u32_to_nat ((Base.W32 0x200))))))))))), (f_weighted_declaration_batches (v_rest) (v_right) (v_remaining) (v_right_weight) ((Base.bool_or ((Base.nat_is_le (v_remaining) (1))) ((Base.bool_and ((Base.nat_is_le (v_remaining) (4))) ((Base.nat_is_le (v_right_weight) ((Base.u32_to_nat ((Base.W32 0x200))))))))))))))))))))
| (_, _) ->
(DeclarationLeaf ((f_declaration_nodes (v_nodes) ([])))))
and (* lower.bend:2839 *)
f_declaration_batches : int -> (C.t_Cst) list -> int -> bool -> t_DeclarationBatch =
fun v_depth v_nodes v_count v_small ->
(match v_small with
| true ->
(DeclarationLeaf (v_nodes))
| false ->
(let v_weighted = (f_weigh_declarations (v_nodes) ([])) in
(f_weighted_declaration_batches (v_depth) (v_weighted) (v_count) ((f_declaration_weight (v_weighted) (0))) (false))))
and (* lower.bend:2849 *)
f_merge_declarations : (M.t_Diagnostic, M.t_Module) Base.result_ -> (M.t_Diagnostic, M.t_Module) Base.result_ -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_left v_right ->
(match v_right with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done (v_b)) ->
(match v_left with
| Fail __error -> Fail __error
| Done v_a ->
(Done ((f_combine_modules (v_a) (v_b))))))
and (* lower.bend:2858 *)
f_lower_declaration_batch : t_DeclarationBatch -> Base.text -> Base.text -> bool -> int -> t_Context -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_batch v_prefix v_module_name v_entry_module v_fuel v_context ->
(match v_batch with
| (DeclarationLeaf (v_nodes)) ->
(f_lower_declarations_sequential (v_nodes) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))
| (DeclarationFork ((DeclarationFork ((DeclarationFork (v_a, v_b)), (DeclarationFork (v_c, v_d)))), (DeclarationFork ((DeclarationFork (v_e, v_f)), (DeclarationFork (v_g, v_h)))))) ->
(let (v_ra, v_rb, v_rc, v_rd, v_re, v_rf, v_rg, v_rh) = Native_parallel.eight (fun () -> (f_lower_declaration_batch (v_a) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) (fun () -> (f_lower_declaration_batch (v_b) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) (fun () -> (f_lower_declaration_batch (v_c) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) (fun () -> (f_lower_declaration_batch (v_d) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) (fun () -> (f_lower_declaration_batch (v_e) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) (fun () -> (f_lower_declaration_batch (v_f) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) (fun () -> (f_lower_declaration_batch (v_g) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) (fun () -> (f_lower_declaration_batch (v_h) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) in
(f_merge_declarations ((f_merge_declarations ((f_merge_declarations (v_ra) (v_rb))) ((f_merge_declarations (v_rc) (v_rd))))) ((f_merge_declarations ((f_merge_declarations (v_re) (v_rf))) ((f_merge_declarations (v_rg) (v_rh)))))))
| (DeclarationFork ((DeclarationFork (v_a, v_b)), (DeclarationFork (v_c, v_d)))) ->
(let (v_ra, v_rb, v_rc, v_rd) = Native_parallel.four (fun () -> (f_lower_declaration_batch (v_a) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) (fun () -> (f_lower_declaration_batch (v_b) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) (fun () -> (f_lower_declaration_batch (v_c) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) (fun () -> (f_lower_declaration_batch (v_d) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) in
(f_merge_declarations ((f_merge_declarations (v_ra) (v_rb))) ((f_merge_declarations (v_rc) (v_rd)))))
| (DeclarationFork (v_left, v_right)) ->
(let (v_a, v_b) = Native_parallel.two (fun () -> (f_lower_declaration_batch (v_left) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) (fun () -> (f_lower_declaration_batch (v_right) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context))) in
(f_merge_declarations (v_a) (v_b))))
and (* lower.bend:2874 *)
f_validate_declaration_nodes : (C.t_Cst) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_nodes ->
(match v_nodes with
| [] ->
(Done (()))
| (v_head :: v_tail) ->
(match (C.f_one ((C.f_field_values (v_head) (s_65)))) with
| Fail __error -> Fail __error
| Done v_node ->
(f_validate_declaration_nodes (v_tail))))
and (* lower.bend:2883 *)
f_effect_member_requests : (M.t_TypeId) list -> (M.t_Ty) list -> (M.t_Operation) list =
fun v_templates v_arguments ->
(match v_templates with
| [] ->
[]
| (v_template :: v_rest) ->
((M.OperationInstance (v_template, v_arguments)) :: (f_effect_member_requests (v_rest) (v_arguments))))
and (* lower.bend:2890 *)
f_row_label_requests_found : (t_Global) option -> (M.t_Ty) list -> (M.t_Operation) list =
fun v_found v_arguments ->
(match v_found with
| (Some ((Global (v_source, v_core, (OperationTemplateName (v_identity, v_parameters)))))) ->
[(M.OperationInstance (v_identity, v_arguments))]
| (Some ((Global (v_source, v_core, (EffectFamilyName (v_members, v_parameters)))))) ->
(f_effect_member_requests (v_members) (v_arguments))
| _ ->
[])
and (* lower.bend:2899 *)
f_row_arguments : (t_Global) option -> (A.t_Value) list -> C.t_Cst -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_found v_values v_node ->
(match v_found with
| (Some ((Global (v_source, v_core, (OperationTemplateName (v_identity, v_parameters)))))) ->
(A.f_bind (v_parameters) (v_values) (v_node))
| (Some ((Global (v_source, v_core, (EffectFamilyName (v_members, v_parameters)))))) ->
(A.f_bind (v_parameters) (v_values) (v_node))
| _ ->
(A.f_bind ([]) (v_values) (v_node)))
and (* lower.bend:2908 *)
f_row_label_requests : T.t_RowLabel -> int -> t_Context -> (T.t_Variable) list -> (M.t_Diagnostic, (M.t_Operation) list) Base.result_ =
fun v_application v_fuel v_context v_variables ->
(let (T.RowLabel (v_name, v_nodes, v_node)) = v_application in
(let (Context (v_globals, v_headers, v_fixities, v_locals, v_label, v_annotation_variables)) = v_context in
(match (T.f_evaluate (f_lookup_effect) (v_fuel) ((T.Nodes (v_nodes))) (v_headers) (v_variables) (v_globals)) with
| Fail __error -> Fail __error
| Done v_values ->
(match (Done ((f_lookup_global (v_globals) (v_name)))) with
| Fail __error -> Fail __error
| Done v_found ->
(match (f_row_arguments (v_found) (v_values) (v_node)) with
| Fail __error -> Fail __error
| Done v_arguments ->
(Done ((f_row_label_requests_found (v_found) (v_arguments)))))))))
and (* lower.bend:2917 *)
f_row_labels_requests : (C.t_Cst) list -> int -> t_Context -> (T.t_Variable) list -> (M.t_Operation) list -> (M.t_Diagnostic, (M.t_Operation) list) Base.result_ =
fun v_nodes v_fuel v_context v_variables v_reversed ->
(match v_nodes with
| [] ->
(Done ((Base.list_reverse (v_reversed))))
| (v_node :: v_rest) ->
(match (T.f_row_label (v_fuel) ((T.f_visit (v_node))) ([]) (v_node)) with
| Fail __error -> Fail __error
| Done v_application ->
(match (f_row_label_requests (v_application) (v_fuel) (v_context) (v_variables)) with
| Fail __error -> Fail __error
| Done v_requests ->
(f_row_labels_requests (v_rest) (v_fuel) (v_context) (v_variables) ((Base.list_reverse_go (v_requests) (v_reversed)))))))
and (* lower.bend:2927 *)
f_row_requests_of : bool -> C.t_Cst -> int -> t_Context -> (T.t_Variable) list -> (M.t_Diagnostic, (M.t_Operation) list) Base.result_ =
fun v_is_row v_node v_fuel v_context v_variables ->
(match v_is_row with
| true ->
(f_row_labels_requests ((C.f_field_values (v_node) (s_309))) (v_fuel) (v_context) (v_variables) ([]))
| false ->
(Done ([])))
and (* lower.bend:2934 *)
f_declaration_row_requests : int -> (C.t_Cst) list -> t_Context -> (T.t_Variable) list -> (M.t_Operation) list -> (M.t_Diagnostic, (M.t_Operation) list) Base.result_ =
fun v_fuel v_nodes v_context v_variables v_reversed ->
(match (v_fuel, v_nodes) with
| (0, _) ->
(Fail ((M.Diagnostic (s_47, s_82, s_310))))
| (__nat_42, []) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
(Done ((Base.list_reverse (v_reversed)))))
| (__nat_43, (v_node :: v_tail)) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(match (f_row_requests_of ((M.f_name_equal ((C.f_kind_of (v_node))) (s_311))) (v_node) (v_rest) (v_context) (v_variables)) with
| Fail __error -> Fail __error
| Done v_requests ->
(f_declaration_row_requests (v_rest) ((Base.list_reverse_go ((Base.list_reverse ((C.f_children_of (v_node))))) (v_tail))) (v_context) (v_variables) ((Base.list_reverse_go (v_requests) (v_reversed)))))))
and (* lower.bend:2945 *)
f_declaration_type_variables : t_NodeKind -> C.t_Cst -> (M.t_Diagnostic, (T.t_Variable) list) Base.result_ =
fun v_kind v_node ->
(match v_kind with
| DataNode ->
(f_type_variables (v_node))
| EffectTypeNode ->
(f_type_variables (v_node))
| _ ->
(T.f_free_variables (v_node) (s_46)))
and (* lower.bend:2954 *)
f_declarations_row_requests : (C.t_Cst) list -> int -> t_Context -> (M.t_Operation) list -> (M.t_Diagnostic, (M.t_Operation) list) Base.result_ =
fun v_nodes v_fuel v_context v_reversed ->
(match v_nodes with
| [] ->
(Done ((Base.list_reverse (v_reversed))))
| (v_head :: v_tail) ->
(match (C.f_one ((C.f_field_values (v_head) (s_65)))) with
| Fail __error -> Fail __error
| Done v_node ->
(match (f_declaration_type_variables ((f_classify ((C.f_kind_of (v_node))))) (v_node)) with
| Fail __error -> Fail __error
| Done v_variables ->
(match (f_declaration_row_requests (v_fuel) ([v_node]) (v_context) (v_variables) ([])) with
| Fail __error -> Fail __error
| Done v_first ->
(f_declarations_row_requests (v_tail) (v_fuel) (v_context) ((Base.list_reverse_go (v_first) (v_reversed))))))))
and (* lower.bend:2965 *)
f_lower_declarations : (C.t_Cst) list -> Base.text -> Base.text -> bool -> int -> t_Context -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_nodes v_prefix v_module_name v_entry_module v_fuel v_context ->
(let v_count = (Base.list_length (v_nodes)) in
(match (f_validate_declaration_nodes (v_nodes)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_lower_declaration_batch ((f_declaration_batches (48) (v_nodes) (v_count) ((Base.nat_is_le (v_count) (4))))) (v_prefix) (v_module_name) (v_entry_module) (v_fuel) (v_context)) with
| Fail __error -> Fail __error
| Done v_module ->
(match (f_declarations_row_requests (v_nodes) (v_fuel) (v_context) ([])) with
| Fail __error -> Fail __error
| Done v_requests ->
(Done ((f_add_operations (v_module) (v_requests))))))))
and (* lower.bend:2980 *)
f_prepare_prelude : C.t_Cst -> int -> (M.t_Diagnostic, t_Prelude) Base.result_ =
fun v_prelude v_fuel ->
(let v_prelude_nodes = (C.f_field_values (v_prelude) (s_314)) in
(match (f_collect_names (v_prelude_nodes) (s_312) (s_313)) with
| Fail __error -> Fail __error
| Done v_prelude_scope ->
(match (f_collect_fixities (v_prelude_nodes) (v_prelude_scope) (false)) with
| Fail __error -> Fail __error
| Done v_prelude_fixities ->
(match (f_lower_declarations (v_prelude_nodes) (s_312) (s_313) (false) (v_fuel) ((f_with_fixities (v_prelude_scope) (v_prelude_fixities)))) with
| Fail __error -> Fail __error
| Done v_prelude_module ->
(Done ((Prelude (v_prelude_module, (f_with_fixities (v_prelude_scope) (v_prelude_fixities))))))))))
and (* lower.bend:2988 *)
f_require_resolved_imports : (C.t_Cst) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_nodes ->
(match v_nodes with
| [] ->
(Done (()))
| (v_node :: v_tail) ->
(Fail ((C.f_diagnostic (v_node) (s_315) (s_316)))))
and (* lower.bend:2995 *)
f_prepare_source : C.t_Cst -> t_Prelude -> (M.t_Diagnostic, t_SourcePlan) Base.result_ =
fun v_root v_prepared ->
(let (Prelude (v_prelude_module, v_public_scope)) = v_prepared in
(let v_nodes = (C.f_field_values (v_root) (s_314)) in
(match (f_require_resolved_imports ((C.f_field_values (v_root) (s_318)))) with
| Fail __error -> Fail __error
| Done v_imports ->
(match (f_collect_names (v_nodes) (s_46) (s_317)) with
| Fail __error -> Fail __error
| Done v_local_scope ->
(match (Done ((f_combine_context (v_local_scope) (v_public_scope)))) with
| Fail __error -> Fail __error
| Done v_scope ->
(match (f_collect_fixities (v_nodes) (v_scope) (false)) with
| Fail __error -> Fail __error
| Done v_fixities ->
(Done ((SourcePlan (v_prelude_module, (f_with_fixities (v_scope) (v_fixities)), v_nodes))))))))))
and (* lower.bend:3005 *)
f_lower_source_declaration : C.t_Cst -> t_Context -> int -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_node v_context v_fuel ->
(f_lower_declarations ([v_node]) (s_46) (s_317) (true) (v_fuel) (v_context))
and (* lower.bend:3008 *)
f_lower_plan : t_SourcePlan -> int -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_plan v_fuel ->
(let (SourcePlan (v_prelude_module, v_scope, v_nodes)) = v_plan in
(match (f_lower_declarations (v_nodes) (s_46) (s_317) (true) (v_fuel) (v_scope)) with
| Fail __error -> Fail __error
| Done v_module ->
(Done ((f_combine_modules (v_prelude_module) (v_module))))))
and (* lower.bend:3014 *)
f_source_module : C.t_Cst -> C.t_Cst -> int -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_root v_prelude v_fuel ->
(match (f_prepare_prelude (v_prelude) (v_fuel)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(match (f_prepare_source (v_root) (v_prepared)) with
| Fail __error -> Fail __error
| Done v_plan ->
(f_lower_plan (v_plan) (v_fuel))))
