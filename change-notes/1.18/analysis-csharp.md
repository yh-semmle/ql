# Improvements to C# analysis

> NOTES
>
> Please describe your changes in terms that are suitable for
> customers to read. These notes will have only minor tidying up
> before they are published as part of the release notes.

## General improvements

* Control flow analysis has been improved for `catch` clauses with filters.

## New queries

| **Query**                   | **Tags**  | **Purpose**                                                        |
|-----------------------------|-----------|--------------------------------------------------------------------|
| Arbitrary file write during zip extraction ("Zip Slip") (`cs/zipslip`) | security, external/cwe/cwe-022  | Identifies zip extraction routines which allow arbitrary file overwrite vulnerabilities.
| Local scope variable shadows member (`cs/local-shadows-member`) | maintainability, readability | Replaces the existing queries Local variable shadows class member (`cs/local-shadows-class-member`), Local variable shadows struct member (`cs/local-shadows-struct-member`), Parameter shadows class member (`cs/parameter-shadows-class-member`), and Parameter shadows struct member (`cs/parameter-shadows-struct-member`). |

## Changes to existing queries

| **Query**                  | **Expected impact**    | **Change**                                                       |
|----------------------------|------------------------|------------------------------------------------------------------|
| [Constant condition](https://help.semmle.com/wiki/display/CSHARP/Constant+condition) (`cs/constant-condition`) | More results | The query has been generalized to cover both Null-coalescing left operand is constant (`cs/constant-null-coalescing`) and Switch selector is constant (`cs/constant-switch-selector`). |
| Exposing internal representation (`cs/expose-implementation`) | Different results | The query has been rewritten, based on the [equivalent Java query](https://help.semmle.com/wiki/display/JAVA/Exposing+internal+representation). |
| Local variable shadows class member(`cs/local-shadows-class-member`) | No results | The query has been replaced by Local scope variable shadows member  (`cs/local-shadows-member`). |
| Local variable shadows struct member (`cs/local-shadows-struct-member`) | No results | The query has been replaced by Local scope variable shadows member  (`cs/local-shadows-member`). |
| [Missing Dispose call on local IDisposable](https://help.semmle.com/wiki/display/CSHARP/Missing+Dispose+call+on+local+IDisposable) (`cs/local-not-disposed`) | Fewer results | The query identifies more cases where the local variable may be disposed by a library call. |
| [Nested loops with same variable](https://help.semmle.com/wiki/display/CSHARP/Nested+loops+with+same+variable) (`cs/nested-loops-with-same-variable`) | Fewer results | Results are no longer highlighted in nested loops that share the same condition, and do not use the variable after the inner loop. |
| Null-coalescing left operand is constant (`cs/constant-null-coalescing`) | No results | The query has been removed, as it is now covered by Constant condition (`cs/constant-condition`). |
| Parameter shadows class member (`cs/parameter-shadows-class-member`) | No results | The query has been replaced by Local scope variable shadows member  (`cs/local-shadows-member`). |
| Parameter shadows struct member (`cs/parameter-shadows-struct-member`) | No results | The query has been replaced by Local scope variable shadows member  (`cs/local-shadows-member`). |
| [Potentially incorrect CompareTo(...) signature](https://help.semmle.com/wiki/display/CSHARP/Potentially+incorrect+CompareTo%28...%29+signature) (`cs/wrong-compareto-signature`) | Fewer results | Results are no longer highlighted in constructed types. |
| Switch selector is constant (`cs/constant-switch-selector`) | No results | The query has been removed, as it is now covered by Constant condition (`cs/constant-condition`). |
| [Useless upcast](https://help.semmle.com/wiki/display/CSHARP/Useless+upcast) (`cs/useless-upcast`) | Fewer results | The query has been improved to cover more cases where upcasts may be needed. |

## Changes to code extraction

* *Series of bullet points*

## Changes to QL libraries

* A new non-member predicate `mayBeDisposed()` can be used to determine if a variable is potentially disposed inside a library. It will analyse the CIL code in the library to determine this.