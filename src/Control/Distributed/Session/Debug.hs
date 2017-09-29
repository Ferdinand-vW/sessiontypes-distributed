{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RebindableSyntax #-}
-- | This module describes an interpreter for purely evaluating session typed programs
--
-- that is based on the paper /Beauty in the beast/ by /Swierstra, W., & Altenkirch, T./
--
-- Impurity in a session typed programs mainly comes from three things: receives, branching and lifting.
--
-- * Using the session type we can easily determine the type of the message that each receive should expect.
-- This information allows us to define a stream of values of different types that provides input for each receive.
--
-- * When evaluating a session we send and receive integers to choose a branch in a selection and offering respectively.
-- If we want to purely evaluate a session typed program, then we must provide some kind of input that makes this choice for us.
-- * The current structure of the `Lift` constructor does not allow us to purely evaluate a `Lift`.
-- As such a session typed program may not contain a lift for it to be purely evaluated. See `runM` as an alternative.
module Control.Distributed.Session.Debug (
  -- * Pure
  run,
  runAll,
  runSingle,
  runP,
  runAllP,
  runSingleP,
  runM,
  runAllM,
  runSingleM,
  -- * Input
  D.Stream(..),
  -- * Output
  D.Output(..),
)
where

import           Control.SessionTypes
import           Control.SessionTypes.Indexed
import qualified Control.SessionTypes.Debug as D
import           Control.Distributed.Session.Session
import           Control.Distributed.Process


-- | Purely evaluates a given `Session` using the input defined by `Stream`.
-- 
-- The output is described in terms of the session type actions within the given program
--
-- An example of how to use this function goes as follows:
--
-- @
--  prog :: Session ('Cap '[] (Int :!> String :?> Eps)) ('Cap '[] Eps) String
--  prog = send 5 >> recv >>= eps
--
--  strm = S_Send $ S_Recv "foo" S_Eps
-- @
--
-- >>> run prog strm
-- O_Send 5 $ O_Recv "foo" $ O_Eps "foo"
run :: HasConstraint Show s => Session s ('Cap ctx Eps) a -> D.Stream s -> D.Output s a
run sess strm = D.run (runSession sess Nothing) strm

-- | Instead of describing the session typed actions, it returns a list of the results
-- of all branches of all offerings.
--
-- @
-- prog = offer (eps 10) (eps 5)
-- strm = S_OffS S_Eps S_Eps
-- @
--
-- >>> runAll prog strm
-- [10,5]
runAll :: HasConstraint Show s => Session s ('Cap ctx Eps) a -> D.Stream s -> [a]
runAll sess strm = D.runAll (runSession sess Nothing) strm

-- | Same as `runAll` but applies `head` to the resulting list
--
-- >>> runSingle prog strm
-- 10
runSingle :: HasConstraint Show s => Session s ('Cap ctx Eps) a -> D.Stream s -> a
runSingle sess strm = D.runSingle (runSession sess Nothing) strm

-- | `run` cannot deal with lifted computations. This makes it limited to session typed programs without any use of lift.
--
-- This function allows us to evaluate lifted computations, but as a consequence is no longer entirely pure.
runP :: HasConstraint Show s => Session s ('Cap ctx Eps) a -> SessionInfo -> D.Stream s -> Process (D.Output s a)
runP sess si strm = D.runM (runSession sess $ Just si) strm

-- | Monadic version of `runAll`.
runAllP :: HasConstraint Show s => Session s ('Cap ctx Eps) a -> SessionInfo -> D.Stream s -> Process [a]
runAllP sess si strm = D.runAllM (runSession sess $ Just si) strm

-- | Monad version of `runSingle`
runSingleP :: HasConstraint Show s => Session s ('Cap ctx Eps) a -> SessionInfo -> D.Stream s -> Process a
runSingleP sess si strm = D.runSingleM (runSession sess $ Just si) strm

-- | Session typed version of `runP`
runM :: HasConstraint Show s => Session s ('Cap ctx Eps) a -> D.Stream s -> Session r r (D.Output s a)
runM sess strm = ask >>= \si -> liftP $ D.runM (runSession sess si) strm

-- | Session typed version of `runAllP`
runAllM :: HasConstraint Show s => Session s ('Cap ctx Eps) a -> D.Stream s -> Session r r [a]
runAllM sess strm = ask >>= \si -> liftP $ D.runAllM (runSession sess si) strm

-- | Session typed version of `runSingleP`
runSingleM :: HasConstraint Show s => Session s ('Cap ctx Eps) a -> D.Stream s -> Session r r a
runSingleM sess strm = ask >>= \si -> liftP $ D.runSingleM (runSession sess si) strm