const extensions = {
  "AllowAmbiguousTypes": {
    "description": "Allow the user to write ambiguous types, and the type inference engine to infer them.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XAllowAmbiguousTypes"
  },
  "ApplicativeDo": {
    "description": "Allows do-notation for types that are Applicative as well as Monad. When enabled, desugaring do notation tries to use (*) and fmap and join as far as possible.",
    "link": "https://ghc.haskell.org/trac/ghc/wiki/ApplicativeDo#Summary"
  },
  "Arrows": {
    "description": "Enable arrow notation.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XArrows"
  },
  "AutoDeriveTypeable": {
    "description": "(deprecated) Deprecated in favour of DeriveDataTypeable.",
    "link": "https://haskell.org/ghc/docs/7.8.4/html/users_guide/deriving.html#auto-derive-typeable"
  },
  "BangPatterns": {
    "description": "Enable a form of pattern which forces evaluation before an attempted match, and a form of strict let/where binding.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XBangPatterns"
  },
  "BinaryLiterals": {
    "description": "Allow the use of binary integer literal syntax (e.g. 0b11001001 to denote 201).",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XBinaryLiterals"
  },
  "BlockArguments": {
    "description": "Allow do blocks etc. in argument position.",
    "link":"https://github.com/ghc-proposals/ghc-proposals/blob/master/proposals/0010-block-arguments.rst#blockarguments-extension"
  },
  "CApiFFI": {
    "description": "Allow use of CAPI FFI calling convention (foreign import capi).",
    "link": "https://haskell.org/ghc/docs/latest/html/users_guide/ffi-chap.html#the-capi-calling-convention"
  },
  "CPP": {
    "description": "Run the C preprocessor on Haskell source code.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#language-pragma"
  },
  "ConstrainedClassMethods": {
    "description": "Allow a class method's type to place additional constraints on a class type variable.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XConstrainedClassMethods"
  },
  "ConstraintKinds": {
    "description": "Allow type classimplicit parameterequality constraints to be used as types with the special kind constraint.  Also generalise the (ctxt => ty) syntax so that any type of kind constraint can occur before the arrow.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XConstraintKinds"
  },
  "DataKinds": {
    "description": "Enable datatype promotion.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XDataKinds"
  },
  "DatatypeContexts": {
    "description": "Allow contexts to be put on datatypes, e.g. the Eq a in data Eq a => Set a = NilSet | ConsSet a (Set a).",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XDatatypeContexts"
  },
  "DefaultSignatures": {
    "description": "Enable support for default signatures.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XDefaultSignatures"
  },
  "DeriveAnyClass": {
    "description": "Enable deriving for any class.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XDeriveAnyClass"
  },
  "DeriveDataTypeable": {
    "description": "Enable deriving for classes Typeable and Data.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XDeriveDataTypeable"
  },
  "DeriveFoldable": {
    "description": "Enable deriving for the Foldable class.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XDeriveFoldable"
  },
  "DeriveFunctor": {
    "description": "Enable deriving for the Functor class.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XDeriveFunctor"
  },
  "DeriveGeneric": {
    "description": "Enable deriving for Generic and Generic1.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XDeriveGeneric"
  },
  "DeriveLift": {
    "description": "Enable deriving for the Lift class.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XDeriveLift"
  },
  "DeriveTraversable": {
    "description": "Enable deriving for the Traversable class.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XDeriveTraversable"
  },
  "DerivingStrategies": {
    "description": "Allow multiple deriving clauses, each optionally qualified with a strategy.",
    "link":"https://ghc.haskell.org/trac/ghc/wiki/Commentary/Compiler/DerivingStrategies"
  },
  "DisambiguateRecordFields": {
    "description": "Allow a record field name to be disambiguated by the type of the record it's in.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XDisambiguateRecordFields"
  },
  "DoAndIfThenElse": {
    "description": "Improve the layout rule when if expressions are used in a do block.",
    "link":"https://prime.haskell.org/wiki/DoAndIfThenElse"
  },
  "DoRec": {
    "description": "(deprecated) Deprecated in favour of RecursiveDo.",
    "link": "http://hackage.haskell.org/package/Cabal-2.4.1.0/docs/Language-Haskell-Extension.html#v:RecursiveDo"
  },
  "DuplicateRecordFields": {
    "description": "Allow records to use duplicated field labels for accessors.",
    "link": "https://ghc.haskell.org/trac/ghc/wiki/Records/OverloadedRecordFields/DuplicateRecordFields"
  },
  "EmptyCase": {
    "description": "Enable case expressions that have no alternatives. Also applies to lambda-case expressions if they are enabled.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XEmptyCase"
  },
  "EmptyDataDecls": {
    "description": "Allow data type declarations with no constructors.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XEmptyDataDecls"
  },
  "ExistentialQuantification": {
    "description": "Allow existentially-quantified data constructors.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XExistentialQuantification"
  },
  "ExplicitForAll": {
    "description": "Make forall a keyword in types, which can be used to give the generalisation explicitly.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XExplicitForAll"
  },
  "ExplicitNamespaces": {
    "description": "Enable explicit namespaces in module import/export lists.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XExplicitNamespaces"
  },
  "ExtendedDefaultRules": {
    "description": "Allow default instantiation of polymorphic types in more situations.",
    "link": "http://downloads.haskell.org/~ghc/latest/docs/html/users_guide/ghci.html#type-defaulting-in-ghci"
  },
  "ExtensibleRecords": {
    "description": "Enable the \"Trex\" extensible records system.",
    "link": "http://haskell.org/hugs/pages/users_guide/hugs-only.html#TREX"
  },
  "FlexibleContexts": {
    "description": "Relax some restrictions on the form of the context of a type signature.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XFlexibleContexts"
  },
  "FlexibleInstances": {
    "description": "Relax some restrictions on the form of the context of an instance declaration.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XFlexibleInstances"
  },
  "ForeignFunctionInterface": {
    "description": "Enable the Foreign Function Interface.  In GHC, implements the standard Haskell 98 Foreign Function Interface Addendum, plus some GHC-specific extensions.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#language-pragma"
  },
  "FunctionalDependencies": {
    "description": "Allow a specification attached to a multi-parameter type class which indicates that some parameters are entirely determined by others. The implementation will check that this property holds for the declared instances, and will use this property to reduce ambiguity in instance resolution.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XFunctionalDependencies"
  },
  "GADTSyntax": {
    "description": "Enable GADT syntax for declaring ordinary algebraic datatypes.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XGADTSyntax"
  },
  "GADTs": {
    "description": "Enable generalized algebraic data types, in which type variables may be instantiated on a per-constructor basis. Implies GADTSyntax.",
    "link": "https://haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#generalised-algebraic-data-types-gadts"
  },
  "GHCForeignImportPrim": {
    "description": "Allow GHC primops, written in C--, to be imported into a Haskell file.",
    "link":"https://ghc.haskell.org/trac/ghc/wiki/Commentary/PrimOps"
  },
  "GeneralizedNewtypeDeriving": {
    "description": "Allow a type declared with newtype to use deriving for any class with an instance for the underlying type.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XGeneralizedNewtypeDeriving"
  },
  "Generics": {
    "description": "(deprecated) Enable generic type classes, with default instances defined in terms of the algebraic structure of a type.",
    "link": "https://haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#generic-classes"
  },
  "HereDocuments": {
    "description": "Enable an alternate syntax for string literals, with string templating.",
    "link": "http://haskell.org/hugs/pages/users_guide/here-documents.html"
  },
  "HexFloatLiterals": {
    "description": "Allow use of hexadecimal literal notation for floating-point values.",
    "link":"https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#hex-float-literals"
  },
  "ImplicitParams": {
    "description": "Enable implicit function parameters with dynamic scope.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XImplicitParams"
  },
  "ImplicitPrelude": {
    "description": "Enable the implicit importing of the module Prelude.  When disabled, when desugaring certain built-in syntax into ordinary identifiers, use whatever is in scope rather than the Prelude -- version.",
    "link": "https://haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#rebindable-syntax-and-the-implicit-prelude-import"
  },
  "ImpredicativeTypes": {
    "description": "(deprecated) Allow a type variable to be instantiated at a polymorphic type.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XImpredicativeTypes"
  },
  "IncoherentInstances": {
    "description": "Implies OverlappingInstances. Allow the implementation to choose an instance even when it is possible that further instantiation of types will lead to a more specific instance being applicable.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XIncoherentInstances"
  },
  "InstanceSigs": {
    "description": "Allow type signatures to be specified in instance declarations.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XInstanceSigs"
  },
  "InterruptibleFFI": {
    "description": "Enable interruptible FFI.",
    "link": "https://haskell.org/ghc/docs/latest/html/users_guide/ffi-chap.html#interruptible-foreign-calls"
  },  
  "KindSignatures": {
    "description": "Allow an explicit kind signature giving the kind of types over which a type variable ranges.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XKindSignatures"
  },
  "LambdaCase": {
    "description": "Enable support lambda-case expressions.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XLambdaCase"
  },
  "LiberalTypeSynonyms": {
    "description": "Defer validity checking of types until after expanding type synonyms, relaxing the constraints on how synonyms may be used.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XLiberalTypeSynonyms"
  },
  "MagicHash": {
    "description": "Allow the character # as a postfix modifier on identifiers.  Also enables literal syntax for unboxed values.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XMagicHash"
  },
  "MonadComprehensions": {
    "description": "Enable monad comprehensions, which generalise the list comprehension syntax to work for any monad.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XMonadComprehensions"
  },
  "MonadFailDesugaring": {
    "description": "A temporary extension to help library authors check if their code will compile with the new planned desugaring of fail.",
    "link":"https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#extension-MonadFailDesugaring"
  },
  "MonoLocalBinds": {
    "description": "Local (let and where) bindings are monomorphic.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XMonoLocalBinds"
  },
  "MonoPatBinds": {
    "description": "(deprecated) Has no effect.",
    "link": "https://downloads.haskell.org/~ghc/7.6.3/docs/html/users_guide/monomorphism.html"
  },
  "MonomorphismRestriction": {
    "description": "Enable the dreaded monomorphism restriction.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XNoMonomorphismRestriction"
  },
  "MultiParamTypeClasses": {
    "description": "Allow multiple parameters in a type class.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XMultiParamTypeClasses"
  },
  "MultiWayIf": {
    "description": "Enable support for multi-way if-expressions.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XMultiWayIf"
  },
  "NPlusKPatterns": {
    "description": "Support for patterns of the form n + k, where k is an integer literal.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XNPlusKPatterns"
  },
  "NamedFieldPuns": {
    "description": "Enable syntax for implicitly binding local names corresponding to the field names of a record.  Puns bind specific names, unlike RecordWildCards.",
    "link": "https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#extension-NamedFieldPuns"
  },
  "NamedWildCards": {
    "description": "Allow named placeholders written with a leading underscore inside type signatures.  Wildcards with the same name unify to the same type.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XNamedWildCards"
  },
  "NegativeLiterals": {
    "description": "Desugars negative literals directly (without using negate).",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XNegativeLiterals"
  },
  "NewQualifiedOperators": {
    "description": "(deprecated) Change the syntax for qualified infix operators.",
    "link": "http://www.haskell.org/ghc/docs/6.12.3/html/users_guide/syntax-extns.html#new-qualified-operators"
  },
  "NondecreasingIndentation": {
    "description": "Enable non-decreasing indentation for do blocks.",
    "link": "https://haskell.org/ghc/docs/latest/html/users_guide/bugs.html#context-free-syntax"
  },
  "NullaryTypeClasses": {
    "description": "Enable support for type classes with no type parameter.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XNullaryTypeClasses"
  },
  "NumDecimals": {
    "description": "Allow the use of floating literal syntax for all instances of Num, including Int and Integer.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XNumDecimals"
  },
  "NumericUnderscores": {
    "description": "Allow use of underscores in numeric literals.",
    "link": "https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#extension-NumericUnderscores"
  },
  "OverlappingInstances": {
    "description": "Allow overlapping class instances, provided there is a unique most specific instance for each use.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XOverlappingInstances"
  },
  "OverloadedLabels": {
    "description": "Allows use of the #label syntax.",
    "link":"https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#extension-OverloadedLabels"
  },
  "OverloadedLists": {
    "description": "Enable overloading of list literals, arithmetic sequences and list patterns using the IsList type class.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XOverloadedLists"
  },
  "OverloadedStrings": {
    "description": "Enable overloading of string literals using a type class, much like integer literals.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XOverloadedStrings"
  },
  "PackageImports": {
    "description": "Allow imports to be qualified by the package name the module is intended to be imported from, e.g.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XPackageImports"
  },
  "ParallelArrays": {
    "description": "Enable parallel arrays syntax ([:, :]) for Data Parallel Haskell.",
    "link": "http://www.haskell.org/haskellwiki/GHC/Data_Parallel_Haskell"
  },
  "ParallelListComp": {
    "description": "Provide syntax for writing list comprehensions which iterate over several lists together, like the zipWith family of functions.",
    "link": "https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#extension-ParallelListComp"
  },
  "PartialTypeSignatures": {
    "description": "Allow anonymous placeholders (underscore) inside type signatures.  The type inference engine will generate a message describing the type inferred at the hole's location.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XPartialTypeSignatures"
  },
  "PatternGuards": {
    "description": "Enable a form of guard which matches a pattern and binds variables.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XPatternGuards"
  },  
  "PatternSynonyms": {
    "description": "Allow giving names to and abstracting over patterns.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XPatternSynonyms"
  },
  "PolyKinds": {
    "description": "Enable kind polymorphism.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XPolyKinds"
  },  
  "PostfixOperators": {
    "description": "Relax the interpretation of left operator sections to allow unary postfix operators.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XPostfixOperators"
  },
  "QuantifiedConstraints": {
    "description": "Allow forall in constraints.",
    "link":"https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#extension-QuantifiedConstraints"
  },
  "QuasiQuotes": {
    "description": "Enable quasi-quotation, a mechanism for defining new concrete syntax for expressions and patterns.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XQuasiQuotes"
  },
  "Rank2Types": {
    "description": "(deprecated) A synonym for RankNTypes.",
    "link": "https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#arbitrary-rank-polymorphism"
  },
  "RankNTypes": {
    "description": "Allow a universally-quantified type to occur on the left of a function arrow.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XRankNTypes"
  },
  "RebindableSyntax": {
    "description": "Makes much of the Haskell sugar be desugared into calls to the function with a particular name that is in scope.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XRebindableSyntax"
  },
  "RecordPuns": {
    "description": "Deprecated, use NamedFieldPuns instead.",
    "link": "https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#record-puns"
  },
  "RecordWildCards": {
    "description": "Enable syntax for implicitly binding local names corresponding to the field names of a record.  A wildcard binds all unmentioned names, unlike NamedFieldPuns.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XRecordWildCards"
  },
  "RecursiveDo": {
    "description": "Allow recursive bindings in do blocks, using the rec keyword, or mdo, a variant of do.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XRecursiveDo"
  },
  "RegularPatterns": {
    "description": "Allow regular pattern matching over lists, as discussed in the paper \"Regular Expression Patterns\" by Niklas Broberg, Andreas Farre and Josef Svenningsson, from ICFP '04.",
    "link":"https://stackoverflow.com/questions/37224366/how-to-resolve-an-unsupported-extension-regularpatterns-error"
  },
  "RelaxedPolyRec": {
    "description": "Relax the requirements on mutually-recursive polymorphic functions.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XRelaxedPolyRec"
  },
  "RestrictedTypeSynonyms": {
    "description": "Enable type synonyms which are transparent in some definitions and opaque elsewhere, as a way of implementing abstract datatypes.",
    "link": "http://haskell.org/hugs/pages/users_guide/restricted-synonyms.html"
  },
  "RoleAnnotations": {
    "description": "Enable explicit role annotations, like in (type role Foo representational representational).",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XRoleAnnotations"
  },
  "Safe": {
    "description": "Compile a module in the Safe, Safe Haskell mode -- a restricted form of the Haskell language to ensure type safety.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/safe_haskell.html#ghc-flag--XSafe"
  },
  "SafeImports": {
    "description": "Allow imports to be qualified with a safe keyword that requires the imported module be trusted as according to the Safe Haskell definition of trust.",
    "link": "https://haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#safe-imports"
  },
  "ScopedTypeVariables": {
    "description": "Cause a type variable in a signature, which has an explicit forall quantifier, to scope over the definition of the accompanying value declaration.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XScopedTypeVariables"
  },
  "StandaloneDeriving": {
    "description": "Allow a standalone declaration which invokes the type class deriving mechanism.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XStandaloneDeriving"
  },
  "StarIsType": {
    "description": "Have * refer to Type.",
    "link":"https://ghc.haskell.org/trac/ghc/wiki/Migration/8.6#StarIsType"
    
  },
  "StaticPointers": {
    "description": "Enable support for 'static pointers' (and the static keyword) to refer to globally stable names, even across different programs.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XStaticPointers"
  },
  "Strict": {
    "description": "Switches all pattern bindings to be strict by default (as if they had a bang using BangPatterns), ordinary patterns are recovered using ~. Implies StrictData.",
    "link": "https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#ghc-flag--XStrict"
  },
  "StrictData": {
    "description": "Switches data type declarations to be strict by default (as if they had a bang using BangPatterns), and allow opt-in field laziness using ~.",
    "link": "https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#ghc-flag--XStrictData"
  },
  "TemplateHaskell": {
    "description": "Enable Template Haskell, a system for compile-time metaprogramming.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XTemplateHaskell"
  },
  "TemplateHaskellQuotes": {
    "description": "A subset of TemplateHaskell including only quoting.",
    "link": "https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#extension-TemplateHaskellQuotes"
  },
  "TraditionalRecordSyntax": {
    "description": "Enable traditional record syntax (as supported by Haskell 98)",
    "link": "https://haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#traditional-record-syntax"
  },
  "TransformListComp": {
    "description": "Enable generalized list comprehensions, supporting operations such as sorting and grouping.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XTransformListComp"
  },
  "Trustworthy": {
    "description": "Compile a module in the Trustworthy, Safe Haskell mode -- no restrictions apply but the module is marked as trusted as long as the package the module resides in is trusted.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/safe_haskell.html#ghc-flag--XTrustworthy"
  },
  "TupleSections": {
    "description": "Enable the use of tuple sections, e.g. (, True) desugars into x -> (x, True).",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XTupleSections"
  },
  "TypeApplications": {
    "description": "Enable explicit type applications with the syntax id @Int.",
    "link":"https://ghc.haskell.org/trac/ghc/wiki/TypeApplication"
  },
  "TypeFamilies": {
    "description": "Allow data types and type synonyms which are indexed by types, i.e. ad-hoc polymorphism for types.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XTypeFamilies"
  },
  "TypeFamilyDependencies": {
    "description": "Allow functional dependency annotations on type families to declare them as injective.",
    "link": "https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#extension-TypeFamilyDependencies"
  },
  "TypeInType": {
    "description": "Dissolve the distinction between types and kinds, allowing the compiler to reason about kind equality and therefore enabling GADTs to be promoted to the type-level.",
    "link":"https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#kind-polymorphism"
  },
  "TypeOperators": {
    "description": "Allow the name of a type constructor, type class, or type variable to be an infix operator.  * https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XTypeOperators",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XTypeOperators"
  },
  "TypeSynonymInstances": {
    "description": "Allow type synonyms in instance heads.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XTypeSynonymInstances"
  },
  "UnboxedSums": {
    "description": "Enable the use of unboxed sum syntax.",
    "link": "https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#extension-UnboxedSums"
  },
  "UnboxedTuples": {
    "description": "Enable unboxed tuples.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XUnboxedTuples"
  },
  "UndecidableInstances": {
    "description": "Ignore structural rules guaranteeing the termination of class instance resolution.  Termination is guaranteed by a fixed-depth recursion stack, and compilation may fail if this depth is exceeded.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XUndecidableInstances"
  },
  "UndecidableSuperClasses": {
    "description": "Allow recursive (and therefore undecideable) super-class relationships.",
    "link": "https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#undecidable-or-recursive-superclasses"
  },
  "UnicodeSyntax": {
    "description": "Allow certain Unicode characters to stand for certain ASCII character sequences, e.g. keywords and punctuation.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XUnicodeSyntax"
  },
  "UnliftedFFITypes": {
    "description": "Allow the use of unboxed types as foreign types, e.g. in foreign import and foreign export.",
    "link": "https://ghc.haskell.org/trac/ghc/wiki/Commentary/PrimOps#Foreignout-of-linePrimOpsandforeignimportprim"
  },
  "Unsafe": {
    "description": "Compile a module in the Unsafe, Safe Haskell mode so that modules compiled using Safe, Safe Haskell mode can't import it.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/safe_haskell.html#ghc-flag--XUnsafe"
  },
  "ViewPatterns": {
    "description": "Enable view patterns, which match a value by applying a function and matching on the result.",
    "link": "https://www.haskell.org/ghc/docs/latest/html/users_guide/glasgow_exts.html#ghc-flag--XViewPatterns"
  },
  "XmlSyntax": {
    "description": "Allow concrete XML syntax to be used in expressions and patterns, as per the Haskell Server Pages extension language: http://www.haskell.org/haskellwiki/HSP. The ideas behind it are discussed in the paper \"Haskell Server Pages through Dynamic Loading\" by Niklas Broberg, from Haskell Workshop '05.",
    "link": "http://www.haskell.org/haskellwiki/HSP"
  }
};


const regexp = new RegExp(Object.keys(extensions).join("|"),"g");

function addLinksToLanguageExtensionsDocs(string) {  
  return string.replace(regexp, function(match) {
    const extension = extensions[match];
    if(extensions) {
      return "<a target='_blank' title='"+extension.description+"' href='"+extension.link+"'>"+match+"</a>";
    } else {
      return match;
    }
  });
};

export {
  addLinksToLanguageExtensionsDocs
}
