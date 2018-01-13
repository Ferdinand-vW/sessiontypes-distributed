{-# LANGUAGE DataKinds #-}
{-# OPTIONS_GHC -Wno-simplifiable-class-constraints #-}
-- | This module provides three functions for normalizing session typed programs.
--
-- With normalizing we mean that we apply rewrites to a session typed program until we can no longer do so
-- and that do not change the semantics of the program.
--
-- The motivation for this module is that for two session typed programs to run as a session they must be dual.
-- Sometimes, one of these programs might not have a session type that is dual to the session type of the other program,
--
-- but we can rewrite the program and therefore also its session type. It is of course important that we do not
-- alter the semantics of the program when rewriting it. For that reason, any rewrite that we may apply must be isomorphic.
--
-- A rewrite is isomorphic if we have two programs \p\ and \p'\, we can do a rewrite from \p\ to \p'\ and from \p'\ to \p\.
--
-- For now two types of rewrites are applied: Elimination of recursive types and flattening of branches.
--
-- An additional benefit of normalizing is that it may lead to further optimizations. 
-- 
-- In "Control.Distributed.Session.Eval" we send an integer for every `Sel` session type that we encounter. By flattening branching
-- we reduce the number of `Sel` constructors and therefore also the number of times one needs to communicate an integer. 
module Control.Distributed.Session.Normalize (
  normalize,
  elimRec,
  flatten
) where

import           Control.SessionTypes
import           Control.SessionTypes.Codensity (rep)
import qualified Control.SessionTypes.Normalize as S

import Control.Distributed.Session.Session

-- | Applies two types of rewrites to a `Session`.
--
-- * Elimination of unused recursion
-- * Rewrites non-right nested branchings to right nested branchings
normalize :: S.Normalize s s' => Session s ('Cap '[] Eps) a -> Session s' ('Cap '[] Eps) a
normalize sess = Session $ \si -> rep $ S.normalize (runSession sess si)

-- | Function for eliminating unused recursive types.
--
-- The function `elimRec` takes a `Session` and traverses the underlying `STTerm`. While doing so, it will attempt to remove `STTerm` constructors annotated with `R` or `Wk` from the program
-- if in doing so does not change the behavior of the program.
--
-- For example, in the following session type we may remove the inner `R` and the `Wk`. 
--
-- > R (R (Wk V))
--
-- We have that the outer `R` matches the recursion variable because of the use of `Wk`. 
--
-- That means the inner `R` does not match any recursion variable (the `R` is unused) and therefore may it and its corresponding constructor be removed from the session.
--
-- We also remove the `Wk`, because the session type pushed into the context by the inner `R` has also been removed.
-- 
-- The generated session type is
--
-- > R V
elimRec :: S.ElimRec s s' => Session s ('Cap '[] Eps) a -> Session s' ('Cap '[] Eps) a
elimRec sess = Session $ \si -> rep $ S.elimRec (runSession sess si)

-- | Flattening of branching
--
-- The function `flatten` takes a `Session` and traverses the underlying `STTerm`. 
-- If it finds a branching session type that has a branch
-- starting with another branching of the same type, then it will extract the branches of the inner branching
-- and inserts these into the outer branching. This is similar to flattening a list of lists to a larger list.
--
-- For example:
--
-- > Sel '[a,b, Sel '[c,d], e]
--
-- becomes
--
-- > Sel '[a,b,c,d,e]
--
-- This only works if the inner branching has the same type as the outer branch (Sel in Sel or Off in Off).
--
-- Also, for now this rewrite only works if one of the branching of the outer branch starts with a new branching.
--
-- For example:
--
-- > Sel '[a,b, Int :!> Sel '[c,d],e]
--
-- does not become
--
-- > Sel '[a,b,Int :!> c, Int :!> d, e]
--
-- Although, this is something that will be added in the future.
flatten :: S.Flatten s s' => Session s ('Cap '[] Eps) a -> Session s' ('Cap '[] Eps) a
flatten sess = Session $ \si -> rep $ S.flatten (runSession sess si)

