{-# LANGUAGE RebindableSyntax      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- | This module defines the `Session` session typed indexed monad.
module Control.Distributed.Session.Session (
  -- * Data types
  Session(..),
  SessionInfo(..),
  runSession,
  -- * Lifting
  liftP,
  liftST
) where

import Control.SessionTypes
import Control.SessionTypes.Codensity
import Control.SessionTypes.Indexed hiding (abs)
import Control.Distributed.Session.STChannel (UTChan)

import Control.Distributed.Process as P (Process, ProcessId, NodeId, liftIO)

-- | `Session` is defined as a newtype wrapper over a function that takes a `Maybe SessionInfo` and returns an indexed codensity monad transformer over the `Process` monad.
--
-- `Session` is also a reader monad that has a Maybe SessionInfo as its environment. `SessionInfo` is wrapped in a `Maybe`, because we also allow a session to be run singularly.
-- In which case there is no other Session to communicate with and therefore is there also no need for a `SessionInfo`.
--
-- The function returns the indexed codensity monad and not simply a `STTerm`, because from benchmarking the codensity monad gave us significant performance improvements for free.
newtype Session s r a = Session { runSessionC :: Maybe SessionInfo -> IxC Process s r a }

-- | The SessionInfo data type tells us information about another `Session`. Namely, the `Session` that is in a session with the `Session` that this specific `SessionInfo` belongs to. 
data SessionInfo = SessionInfo {
  othPid :: ProcessId, -- ^ The `ProcessId` of the dual `Session`
  othNode :: NodeId, -- ^ The `NodeId` of the `Node` that the dual `Session` runs on
  utchan :: UTChan -- ^ A send port belonging to the dual `Session`, such that we can send messages to it. And a receive port of which the dual `Session` has its send port, such that we can receive messages from the dual `Session`.
}

-- | Evaluates a session to a `STTerm`
runSession :: Session s r a -> Maybe SessionInfo -> STTerm Process s r a
runSession (Session c) si = abs $ c si

instance IxFunctor Session where
  fmap f sess = Session $ \si -> fmap f $ runSessionC sess si

instance IxApplicative Session where
  pure = return
  f <*> g = Session $ \si -> (runSessionC f si) <*> (runSessionC g si)

instance IxMonad Session where
  return a = Session $ \_ -> return a
  (Session s) >>= f = Session $ \si -> do
    a <- s si
    let (Session r) = f a
    r si

instance MonadSession Session where
  send a = Session $ const $ send a
  recv = Session $ const recv
  sel1 = Session $ const sel1
  sel2 = Session $ const sel2
  offZ (Session f) = Session $ offZ . f
  offS (Session f) (Session g) = Session $ \si -> offS (f si) (g si) 
  recurse (Session f) = Session $ \si -> recurse (f si)
  weaken (Session f) = Session $ \si -> weaken (f si)
  var (Session f) = Session $ \si -> var $ f si
  eps a = Session $ const $ eps a

instance IxMonadReader (Maybe SessionInfo) Session where
  ask = Session $ \si -> return si
  local f m = Session $ \si -> runSessionC m (f si)
  reader f = Session $ \si -> return (f si)

instance IxMonadIO Session where
  liftIO = liftP . P.liftIO

-- | Lifts a `Process` computation
liftP :: Process a -> Session s s a
liftP p = Session $ \_ -> rep $ lift p

-- | Lifts a `STTerm` computation
liftST :: STTerm Process s r a -> Session s r a
liftST st = Session $ \_ -> rep st