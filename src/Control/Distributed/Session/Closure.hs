{-# LANGUAGE DataKinds  #-}
{-# LANGUAGE GADTs      #-}
-- | We cannot create a `Closure` of a `Session`, because its type parameters are of a different kind than `*`.
--
-- To accomedate for this drawback we define two data types that existentially quantify the type parameters of a `Session`.
--
-- We also define a set of static and closure functions for remotely spawning sessions.
module Control.Distributed.Session.Closure (
  -- * Encapsulation
  SpawnSession (..),
  SessionWrap (..),
  -- * RemoteTable
  sessionRemoteTable,
  -- * Static and Closures
  -- ** Singular
  remoteSessionStatic,
  remoteSessionClosure,
  remoteSessionStatic',
  remoteSessionClosure',
  -- ** SpawnChannel
  spawnChannelStatic,
  spawnChannelClosure,
  -- ** Local Remote Evaluation
  evalLocalSession,
  remoteSpawnSessionStatic,
  remoteSpawnSessionClosure,
  remoteSpawnSessionStatic',
  remoteSpawnSessionClosure',
  -- ** Remote Remote Evaluation
  rrSpawnSessionSendStatic,
  rrSpawnSessionSendClosure,
  rrSpawnSessionExpectStatic,
  rrSpawnSessionExpectClosure
) where

import Control.SessionTypes.Types
import Control.Distributed.Session.Eval
import Control.Distributed.Session.STChannel as ST
import Control.Distributed.Session.Session

import Control.Distributed.Process hiding       (spawnChannel)
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Serializable (Serializable)
import Control.Distributed.Static

import Data.ByteString.Lazy (ByteString)
import Data.Binary          (encode, decode)
import Data.Rank1Dynamic    (toDynamic)
import Data.Rank1Typeable   (ANY, Typeable)

-- | Data type that encapsulates two sessions for the purpose of remotely spawning them
-- 
-- The session types of the sessions are existentially quantified, but we still ensure duality and constrain them properly, such that they can be passed to `evalSession`.
data SpawnSession a b where
  SpawnSession :: (HasConstraintST Serializable s, HasConstraintST Serializable (DualST s), Typeable a, Typeable b) => 
                  Session ('Cap '[] s) r a -> Session ('Cap '[] (DualST s)) r b -> SpawnSession a b

-- | Data type that encapsulates a single session performing no session typed action that can be remotely spawned.
--
-- We use this data type mostly for convenience in combination with `evalSessionEq` allowing us to avoid the `Serializable` constraint.
data SessionWrap a where
  SessionWrap :: Session s s a -> SessionWrap a

-- | Static function for remotely spawning a single session
-- 
-- When remotely spawning any session we must always pass it the `ProcessId` and `NodeId` of the spawning process.
--
-- We must pass a Closure of a `SessionWrap` instead of just a `SessionWrap`, because that would require
-- serializing a `SessionWrap` which is not possible.
--
-- Furthermore, we must also pass a `SerializableDict` that shows how to serialize a value of type `a`.
remoteSessionStatic :: Static (SerializableDict a -> Closure (SessionWrap a) -> Process a)
remoteSessionStatic = staticLabel "$remoteSession"

evalRemoteSession :: SerializableDict a -> Closure (SessionWrap a) -> Process a
evalRemoteSession SerializableDict proc = do
  (SessionWrap sess) <- unClosure proc
  evalSessionEq sess

-- | Closure function for remotely spawning a single session
remoteSessionClosure :: Static (SerializableDict a) -> Closure (SessionWrap a) -> Closure (Process a)
remoteSessionClosure sdict proc = closure decoder (encode proc)
  where decoder = (remoteSessionStatic `staticApply` sdict) `staticCompose` decodeSessionWrap 

-- | Same as `remoteSessionStatic`, except that we do not need to provide a `SerializableDict`.
remoteSessionStatic' :: Static (Closure (SessionWrap ()) -> Process ())
remoteSessionStatic' = staticLabel "$remoteSession'"

evalRemoteSession' :: Closure (SessionWrap ()) -> Process ()
evalRemoteSession' proc = do
  (SessionWrap sess) <- unClosure proc
  evalSessionEq sess

-- | Same as `remoteSessionClosure`, except that we do not need to provide a `SerializableDict`.
remoteSessionClosure' :: Closure (SessionWrap ()) -> Closure (Process ())
remoteSessionClosure' tpl = closure decoder (encode tpl)
  where decoder = remoteSessionStatic' `staticCompose` decodeSessionWrap

-- | A static function specific to the lifted `Control.Distributed.Session.Lifted.spawnChannel` function that can be found in "Control.Distributed.Session.Lifted"
spawnChannelStatic :: Static (SerializableDict a -> Closure (ReceivePort a -> SessionWrap ()) -> ReceivePort a -> Process ())
spawnChannelStatic = staticLabel "$spawnChannel"

spawnChannel :: SerializableDict a -> Closure (ReceivePort a -> SessionWrap ()) -> ReceivePort a -> Process ()
spawnChannel SerializableDict proc rp = do
  (SessionWrap sess) <- unClosure proc >>= \f -> return (f rp)
  evalSessionEq sess

-- | A closure specific to the lifted `spawnChannel` function that can be found in "Control.Distributed.Session.Lifted"
spawnChannelClosure :: Static (SerializableDict a) -> Closure (ReceivePort a -> SessionWrap ()) -> Closure (ReceivePort a -> Process ())
spawnChannelClosure sdict proc = closure decoder (encode proc)
  where decoder = (spawnChannelStatic `staticApply` sdict) `staticCompose` decodeSpawnChannel

-- | Function that evalutes the first argument of a `SpawnSession` in a local manner.
--
-- It is local in that we do not create an accompanying closure.
evalLocalSession :: Typeable a => (ProcessId, NodeId, Closure (SpawnSession a ())) -> Process a
evalLocalSession (pidOth, nodeOth, proc) = do
  (spSelf, rpSelf) <- ST.newUTChan
  send pidOth spSelf 
  spOth <- expect :: Process (SendPort ST.Message)
  (SpawnSession s r) <- unClosure proc
  evalSession s (SessionInfo pidOth nodeOth (spOth, rpSelf))

-- | Static function for remotely evaluating the second argument of a `SpawnSession`.
--
-- This function works dually to `evalLocalSession`.
remoteSpawnSessionStatic :: Static (SerializableDict a -> (ProcessId, NodeId, Closure (SpawnSession a ())) -> Process ())
remoteSpawnSessionStatic = staticLabel "$remoteSpawnSession"
  
evalRemoteSpawnSession :: SerializableDict a -> (ProcessId, NodeId, Closure (SpawnSession a ())) -> Process () 
evalRemoteSpawnSession SerializableDict (pidOth, nodeOth, proc) = do
  (spSelf, rpSelf) <- ST.newUTChan
  send pidOth spSelf 
  spOth <- expect :: Process (SendPort ST.Message)
  (SpawnSession s r) <- unClosure proc
  evalSession r (SessionInfo pidOth nodeOth (spOth, rpSelf))

-- | Closure for remotely evaluating the second argument of a `SpawnSession`
remoteSpawnSessionClosure :: Static (SerializableDict a) -> (ProcessId, NodeId, Closure (SpawnSession a ())) -> Closure (Process ())
remoteSpawnSessionClosure tdictS tpl = closure decoder (encode tpl)
  where decoder :: Static (ByteString -> Process ())
        decoder = (remoteSpawnSessionStatic `staticApply` tdictS) `staticCompose` decodeSpawnSession

-- | Same as `remoteSpawnSessionStatic`, except for that we do not need to provide a `SerializableDict`.
remoteSpawnSessionStatic' :: Static ((ProcessId, NodeId, Closure (SpawnSession () ())) -> Process ())
remoteSpawnSessionStatic' = staticLabel "$remoteSpawnSession'"

evalRemoteSpawnSession' :: (ProcessId, NodeId, Closure (SpawnSession () ())) -> Process () 
evalRemoteSpawnSession' (pidOth, nodeOth, proc) = do
  (spSelf, rpSelf) <- ST.newUTChan
  send pidOth spSelf 
  spOth <- expect :: Process (SendPort ST.Message)
  (SpawnSession _ r) <- unClosure proc
  evalSession r (SessionInfo pidOth nodeOth (spOth, rpSelf))

-- | Same as `remoteSpawnSessionClosure`, except for that we do not need to provide a `SerializableDict`.
remoteSpawnSessionClosure' :: (ProcessId, NodeId, Closure (SpawnSession () ())) -> Closure (Process ())
remoteSpawnSessionClosure' tpl = closure decoder (encode tpl)
  where decoder :: Static (ByteString -> Process ())
        decoder = remoteSpawnSessionStatic' `staticCompose` decodeSpawnSession

-- | Static function for remotely evaluating the second argument of a `SpawnSession`
-- 
-- This function is very similar to `remoteSpawnSessionStatic'`. The difference is that this function assumes that
-- the other session was also remotely spawned. 
--
-- Therefore we require an extra send of the `ProcessId` of the to be spawned process.
rrSpawnSessionSendStatic :: Static ((ProcessId, NodeId, Closure (SpawnSession () ())) -> Process ())
rrSpawnSessionSendStatic = staticLabel "$rrSpawnSessionSend"

rrSpawnSessionSend :: (ProcessId, NodeId, Closure (SpawnSession () ())) -> Process ()
rrSpawnSessionSend (pid, node, proc) = do
  pidSelf <- getSelfPid
  (spSelf, rpSelf) <- ST.newUTChan

  send pid pidSelf
  send pid spSelf

  spOth <- expect :: Process (SendPort ST.Message)

  (SpawnSession _ sess) <- unClosure proc
  evalSession sess (SessionInfo pid node (spOth, rpSelf))

-- | Closure for remotely evaluating the second argument of a `SpawnSession`.
rrSpawnSessionSendClosure :: (ProcessId, NodeId, Closure (SpawnSession () ())) -> Closure (Process ())
rrSpawnSessionSendClosure tpl = closure decoder (encode tpl)
  where decoder :: Static (ByteString -> Process ())
        decoder = rrSpawnSessionSendStatic `staticCompose` decodeSpawnSession

-- | Closure for remotely evaluating the first argument of a `SpawnSession`
--
-- This function acts dual to `rrSpawnSessionSend` and assumes that it will first receive a `ProcessId`.
rrSpawnSessionExpectStatic :: Static ((NodeId, Closure (SpawnSession () ())) -> Process ())
rrSpawnSessionExpectStatic = staticLabel "$rrSpawnSessionExpect"

rrSpawnSessionExpect :: (NodeId, Closure (SpawnSession () ())) -> Process ()
rrSpawnSessionExpect (node, proc) = do
  (spSelf, rpSelf) <- ST.newUTChan

  pidOth <- expect
  send pidOth spSelf
  spOth <- expect :: Process (SendPort ST.Message)

  SpawnSession sess _ <- unClosure proc
  evalSession sess (SessionInfo pidOth node (spOth, rpSelf))

-- | Closure for remotely evaluating the first argument of a `SpawnSession`.
rrSpawnSessionExpectClosure :: (NodeId, Closure (SpawnSession () ())) -> Closure (Process ())
rrSpawnSessionExpectClosure tpl = closure decoder (encode tpl)
  where decoder :: Static (ByteString -> Process ())
        decoder = rrSpawnSessionExpectStatic `staticCompose` decodeSpawnSessionNoPid

decodeSpawnSession :: Static (ByteString -> (ProcessId, NodeId, Closure (SpawnSession a ())))
decodeSpawnSession = staticLabel "$decodeSpawnSession"

decodeSpawnSessionNoPid :: Static (ByteString -> (NodeId, Closure (SpawnSession a ())))
decodeSpawnSessionNoPid = staticLabel "$decodeSpawnSessionNoPid"

decodeSessionWrap :: Static (ByteString -> Closure (SessionWrap a))
decodeSessionWrap = staticLabel "$decodeSessionWrap"

decodeSpawnChannel :: Static (ByteString -> Closure (ReceivePort a -> SessionWrap ()))
decodeSpawnChannel = staticLabel "$decodeSpawnChannel"

-- | RemoteTable that binds all in this module defined static functions to their corresponding evaluation functions.
sessionRemoteTable :: RemoteTable -> RemoteTable
sessionRemoteTable rtable =
  registerStatic "$remoteSession" (toDynamic (evalRemoteSession :: SerializableDict ANY -> Closure (SessionWrap ANY) -> Process ANY)) $
  registerStatic "$remoteSession'" (toDynamic evalRemoteSession') $
  registerStatic "$spawnChannel" (toDynamic (spawnChannel :: SerializableDict ANY -> Closure (ReceivePort ANY -> SessionWrap ()) -> ReceivePort ANY -> Process ())) $
  registerStatic "$remoteSpawnSession" (toDynamic (evalRemoteSpawnSession :: SerializableDict ANY -> (ProcessId, NodeId, Closure (SpawnSession ANY ())) -> Process ())) $
  registerStatic "$remoteSpawnSession'" (toDynamic evalRemoteSpawnSession') $
  registerStatic "$rrSpawnSessionSend" (toDynamic rrSpawnSessionSend) $
  registerStatic "$rrSpawnSessionExpect" (toDynamic rrSpawnSessionExpect) $
  registerStatic "$decodeSpawnSession" (toDynamic (decode :: ByteString -> (ProcessId, NodeId, Closure (SpawnSession ANY ())))) $
  registerStatic "$decodeSpawnSessionNoPid" (toDynamic (decode :: ByteString -> (NodeId, Closure (SpawnSession ANY ())))) $
  registerStatic "$decodeSessionWrap" (toDynamic (decode :: ByteString -> Closure (SessionWrap ANY))) $
  registerStatic "$decodeSpawnChannel" (toDynamic (decode :: ByteString -> Closure (ReceivePort ANY -> SessionWrap ()))) $
  rtable