{-# LANGUAGE DataKinds #-}
-- | This module exposes two functions for interactively evaluation a session typed program
--
-- To run a session you must have two participating actors. In our context, the actors are session typed programs.
-- 
-- Using this module the user will act as one of the actors in the session by suppling values to a receive
--
-- and selecting a branch for offerings.
module Control.Distributed.Session.Interactive (
  interactive,
  interactiveStep
) where

import qualified Control.SessionTypes.Interactive as S
import           Control.SessionTypes.Types
import           Control.Distributed.Session.STChannel (newUTChan)
import           Control.Distributed.Session.Session

import Data.Typeable (Typeable)
import Control.Distributed.Process (Process, getSelfPid, getSelfNode)

-- | For this function the user will act as the dual to the given session. User interaction is only required
-- when the given program does a receive or an offer.
--
-- A possible interaction goes as follows:
--
-- @
-- prog = do
--  send 5
--  x <- recv
--  offer (eps x) (eps "")
--
-- main = interactive prog
-- @
-- 
-- >> Enter value of type String: "test"
-- >> (L)eft or (R)ight: L
-- > "test"
interactive :: (HasConstraints '[Read, Show, Typeable] s, Show a) => Session s r a -> Process a
interactive sess = do
  pid <- getSelfPid
  node <- getSelfNode 
  utchan <- newUTChan

  S.interactive $ runSession sess Nothing

-- | Different from `interactive` is that this function gives the user the choice to abort the session
-- after each session typed action. 
--
-- Furthermore, it also prints additional output describing which session typed action occurred.
interactiveStep :: (HasConstraints '[Read, Show, Typeable] s, Show a) => Session s r a -> Process (Maybe a)
interactiveStep sess = do
  pid <- getSelfPid
  node <- getSelfNode
  utchan <- newUTChan
  
  S.interactiveStep $ runSession sess Nothing