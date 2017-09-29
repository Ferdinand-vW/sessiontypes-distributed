-- | Defines several combinators for spawning sessions
--
-- Here we define a session to be two dual `Session`s that together implement a protocol described by a session type.
--
-- The following shows an example of how to spawn a session
--
-- @
--
-- {-\# LANGUAGE TemplateHaskell \#-}
-- {-\# LANGUAGE DataKinds \#-}
-- {-\# LANGUAGE TypeOperators \#-}
-- 
-- import qualified SessionTypes.Indexed as I
-- import Control.Distributed.Session hiding (getSelfPid, expect)
-- import Control.Distributed.Process (liftIO, Process, RemoteTable, NodeId, getSelfPid, ProcessId, expect)
-- import Control.Distributed.Process.Closure (remotable, mkClosure)
-- import Control.Distributed.Process.Node
-- import Network.Transport.TCP
-- 
-- sess1 :: Session ('Cap '[] (Int :!> Eps)) ('Cap '[] Eps) ()
-- sess1 = send 5 I.>> eps ()
-- 
-- sess2 :: ProcessId -> Session ('Cap '[] (Int :?> Eps)) ('Cap '[] Eps) ()
-- sess2 pid = recv I.>>= \x -> utsend pid x I.>>= eps
-- 
-- spawnSess :: ProcessId -> SpawnSession () ()
-- spawnSess pid = SpawnSession sess1 (sess2 pid)
-- 
-- remotable ['spawnSess]
-- 
-- p1 :: NodeId -> Process ()
-- p1 nid = do
--   pid <- getSelfPid
--   spawnRRSessionP nid nid ($(mkClosure 'spawnSess) pid)
--   a <- expect :: Process Int
--   liftIO (putStrLn $ show a)
-- 
-- myRemoteTable :: RemoteTable
-- myRemoteTable = Main.__remoteTable $ sessionRemoteTable initRemoteTable
-- 
-- main :: IO ()
-- main = do
--   Right t <- createTransport "127.0.0.1" "100000" defaultTCPParameters
--   node <- newLocalNode t myRemoteTable
--   runProcess node $ p1 (localNodeId node)
--
-- @
--
-- >>> main
-- > 5
--
-- In p1 we spawn a session that consists of two `Session`s that are remotely spawned (which happens to be the local node).
--
-- We do so using the `spawnRRSessionP` function that we can call within a `Process`. We pass it the two node identifiers followed
-- by a closure that takes an argument.
--
-- Sess1 and sess2 implement both sides of the protocol. We can insert these into a `SpawnSession`, because they are dual to each other.
-- 
-- > spawnSess :: ProcessId -> SpawnSession () ()
-- > spawnSess pid = SpawnSession sess1 (sess2 pid)
--
-- Then to create a closure for `spawnSess` that we can then pass to `spawnRRSessionP` we first add `spawnSess` to the remotable of the current module.
--
-- > remotable ['spawnSess]
--
-- remotable is a top-level Template Haskell splice that creates a closure function for us.
--
-- To use this closure function we can simply do
--
-- > $(mkClosure 'spawnSess) pid
--
-- We use `mkClosure` such that we can still pass an argument to spawnSess with the result being of type Closure (SpawnSession () ())
--
-- It is important that the node that we run p1 on knows how to evaluate a closure of type Closure (SpawnSession () ()). This requires that we 
-- compose the initRemoteTable of a node with the remotable of this module.
--
-- Within `spawnRRSessionP` we make use of internally defined closures. The library therefore exports `sessionRemoteTable` that should always be passed to a node
-- if you make use of a function within this library that takes a closure as an argument. 
--
-- > myRemoteTable :: RemoteTable
-- > myRemoteTable = Main.__remoteTable $ sessionRemoteTable initRemoteTable
--
-- > node <- newLocalNode t myRemoteTable
module Control.Distributed.Session.Spawn (
  -- * Call
  callLocalSessionP,
  callLocalSession,
  callRemoteSessionP,
  callRemoteSession,
  callRemoteSessionP',
  callRemoteSession',
  -- * Spawn
  spawnLLSessionP,
  spawnLLSession,
  spawnLRSessionP,
  spawnLRSession,
  spawnRRSessionP,
  spawnRRSession
) where

import Control.Distributed.Process as P
import Control.Distributed.Process.Serializable
import Control.SessionTypes
import Control.Distributed.Session.Closure
import Control.Distributed.Session.Eval
import Control.Distributed.Session.Session
import Control.Distributed.Session.STChannel as ST

import Control.Concurrent

-- | Calls a local session consisting of two dual `Session`s. 
-- 
-- Spawns a new local process for the second `Session` and runs the first `Session` on the current process.
--
-- Returns the result of the first `Session` and the `ProcessId` of the second `Session`.
callLocalSessionP :: (HasConstraint Serializable s, 
                      HasConstraint Serializable (Dual s)) => 
                      Session s r a -> Session (Dual s) r b -> P.Process (a, ProcessId)
callLocalSessionP s1 s2 = do
  pidSelf <- P.getSelfPid
  node <- P.getSelfNode
  (sp1, rp1) <- ST.newUTChan
  (sp2, rp2) <- ST.newUTChan

  let si1 = SessionInfo pidSelf node (sp1, rp2) 
  pid <- P.spawnLocal $ evalSession s2 si1 >> return ()
  let si2 = SessionInfo pid node (sp2, rp1)
  a <- evalSession s1 si2
  
  return (a, pid)

-- | Sessioned version of `callLocalSessionP`
callLocalSession :: (HasConstraint Serializable s,
                     HasConstraint Serializable (Dual s)) =>
                     Session s r a -> Session (Dual s) r b -> Session k k (a, ProcessId)
callLocalSession ss1 ss2 = liftP $ callLocalSessionP ss1 ss2

-- | Calls a remote session consisting of two dual `Session`s.
--
-- Spawns a remote process for the second `Session` and runs the first `Session` on the current process.
--
-- Returns the result of the frist `Session` and the `ProcessId` of the second `Session`.
--
-- The arguments of this function are described as follows:
--
-- * Static (SerializableDict a): Describes how to serialize a value of type `a`
-- * NodeId: The node identifier of the node that the second `Session` should be spawned to.
-- * Closure (SpawnSession a ()): A closure of a wrapper over two dual `Session`s.
--
-- Requires `sessionRemoteTable`
callRemoteSessionP :: Serializable a => Static (SerializableDict a) -> NodeId -> Closure (SpawnSession a ()) -> Process (a, ProcessId)
callRemoteSessionP sdict nodeOth proc = do
  pidSelf <- getSelfPid
  nodeSelf <- getSelfNode

  pidOth <- spawn nodeOth $ remoteSpawnSessionClosure sdict ((pidSelf, nodeSelf, proc))
  a <- evalLocalSession (pidOth, nodeOth, proc)
  return (a, pidOth)

-- | Sessioned version of `callRemoteSession`
--
-- Requires `sessionRemoteTable`
callRemoteSession :: Serializable a => Static (SerializableDict a) -> NodeId -> Closure (SpawnSession a ()) -> Session k k (a, ProcessId)
callRemoteSession n1 sdict proc = liftP $ callRemoteSessionP n1 sdict proc

-- | Same as `callRemoteSessionP`, but we no longer need to provide a static serializable dictionary, because the result type of the first session is unit.
--
-- Requires `sessionRemoteTable`
callRemoteSessionP' :: NodeId -> Closure (SpawnSession () ()) -> Process (ProcessId)
callRemoteSessionP' nodeOth proc = do
  pidSelf <- getSelfPid
  nodeSelf <- getSelfNode

  pidOth <- spawn nodeOth $ remoteSpawnSessionClosure' (pidSelf, nodeSelf, proc)
  evalLocalSession (pidOth, nodeOth, proc)
  return pidOth

-- | Sessioned version of `callRemoteSessionP'`
--
-- Requires `sessionRemoteTable`
callRemoteSession' :: NodeId -> Closure (SpawnSession () ()) -> Session s s (ProcessId)
callRemoteSession' node proc = liftP $ callRemoteSessionP' node proc

-- | Spawns a local session.
--
-- Both `Session`s are spawned locally.
--
-- Returns the `ProcessId` of both spawned processes.
spawnLLSessionP :: (HasConstraint Serializable s,
                    HasConstraint Serializable (Dual s)) =>
                    Session s r a -> Session (Dual s) r b -> Process (ProcessId, ProcessId)
spawnLLSessionP sess1 sess2 = do
  nodeSelf <- getSelfNode
  mvar <- liftIO newEmptyMVar
  (sp1, rp1) <- ST.newUTChan
  (sp2, rp2) <- ST.newUTChan

  pid1 <- spawnLocal $ do
    pid <- liftIO $ takeMVar mvar
    evalSession sess1 (SessionInfo pid nodeSelf (sp1, rp2))
    return ()

  pid2 <- spawnLocal $ do
    pid <- getSelfPid
    liftIO $ putMVar mvar pid
    evalSession sess2 (SessionInfo pid1 nodeSelf (sp2, rp1))
    return ()

  return (pid1, pid2)

-- | Sessioned version of `spawnLLSession`
spawnLLSession :: (HasConstraint Serializable s,
                   HasConstraint Serializable (Dual s)) =>
                   Session s  r a -> Session (Dual s) r b -> Session t t (ProcessId, ProcessId)
spawnLLSession st1 st2 = liftP $ spawnLLSessionP st1 st2

-- | Spawns one `Session` local and spawns another `Session` remote.
--
-- Returns the `ProcessId` of both spawned processes.
--
-- The arguments are described as follows:
--
-- * NodeId: The node identifier of the node that the second `Session` should be spawned to.
-- * Closure (SpawnSession () ()): A closure of a wrapper over two dual `Session`s.
--
-- Requires `sessionRemoteTable`
spawnLRSessionP :: NodeId -> Closure (SpawnSession () ()) -> Process (ProcessId, ProcessId)
spawnLRSessionP nodeOth proc = do
  nodeSelf <- getSelfNode
  mvar <- liftIO newEmptyMVar

  pid1 <- spawnLocal $ do
    pid <- liftIO $ takeMVar mvar
    evalLocalSession (pid, nodeOth, proc)
  pid2 <- spawn nodeOth $ remoteSpawnSessionClosure' ((pid1, nodeSelf, proc))
  liftIO $ putMVar mvar pid2

  return (pid1, pid2)

-- | Sessioned version of `spawnLRSessionP`
--
-- Requires `sessionRemoteTable`
spawnLRSession :: NodeId -> Closure (SpawnSession () ()) -> Session s s (ProcessId, ProcessId)
spawnLRSession node proc = liftP $ spawnLRSessionP node proc

-- | Spawns a remote session. Both `Session` arguments are spawned remote.
--
-- Returns the `ProcessId` of both spawned processes.
--
-- The arguments are described as follows:
--
-- * NodeId: The node identifier of the node that the first `Session` should be spawned to.
-- * NodeId: The node identifier of the node that the second `Session` should be spawned to.
-- * Closure (SpawnSession () ()): A closure of a wrapper over two dual `Session`s.
--
-- Requires `sessionRemoteTable`
spawnRRSessionP :: NodeId -> NodeId -> Closure (SpawnSession () ()) -> Process (ProcessId, ProcessId)
spawnRRSessionP n1 n2 proc = do
  pid1 <- spawn n1 (rrSpawnSessionExpectClosure (n2, proc)) -- expect a pid
  pid2 <- spawn n2 (rrSpawnSessionSendClosure (pid1, n1, proc)) -- send a pid

  return (pid1, pid2)

-- | Sessioned version of `SpawnRRSession`
--
-- Requires `sessionRemoteTable`
spawnRRSession :: NodeId -> NodeId -> Closure (SpawnSession () ()) -> Session s s (ProcessId, ProcessId)
spawnRRSession n1 n2 proc = liftP $ spawnRRSessionP n1 n2 proc