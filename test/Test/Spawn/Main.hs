{-# LANGUAGE TemplateHaskell #-}
import Control.Distributed.Session.Spawn
import Control.Distributed.Session.Closure
import Control.Distributed.Process
import Control.Distributed.Process.Node
import Control.Distributed.Process.Closure
import Network.Transport.TCP

import Test.Hspec
import Test.Program.Closure

main :: IO ()
main = do
  n <- newNode 10000
  runProcess n $ do
    let nid = localNodeId n
    x1 <- test_callLocalSession
    x2 <- test_callRemoteSession nid 
    x3 <- test_callRemoteSession' nid
    x4 <- test_spawnLLSession
    x5 <- test_spawnLRSession nid
    x6 <- test_spawnRRSession nid

    liftIO $ do
      hspec $ do
        describe "callLocalSession" $ do
          it "spawns a session and waits for the result of the first process" $ do
              x1 `shouldBe` 0

        describe "callRemoteSession" $ do
          it "spawns a session and waits for the result of the first process" $ do
              x2 `shouldBe` 0

        describe "callRemoteSession'" $ do
          it "spawns a session and waits for the result of the first process" $ do
              x3 `shouldBe` 0

        describe "spawnLLSession" $ do
          it "spawns a local session" $ do
              x4 `shouldBe` 0

        describe "spawnLRSession" $ do
          it "spawns a session, one process is spawned locally and another remote" $ do
              x5 `shouldBe` 0

        describe "spawnRRSession" $ do
          it "spawns a session, both processes are spawned remote" $ do
              x6 `shouldBe` 0
        
myRemoteTable :: RemoteTable
myRemoteTable = Test.Program.Closure.__remoteTable $ sessionRemoteTable initRemoteTable

newNode p = do
  Right t <- createTransport "127.0.0.1" (show p) defaultTCPParameters
  newLocalNode t myRemoteTable

test_callLocalSession :: Process Int
test_callLocalSession = fmap fst $ callLocalSessionP sess1 sess2

test_callRemoteSession :: NodeId -> Process Int
test_callRemoteSession nid = fmap fst $ callRemoteSessionP $(mkStatic 'sdictInt) nid $(mkStaticClosure 'spawnSess)

test_callRemoteSession' :: NodeId -> Process Int
test_callRemoteSession' nid = do
  pid <- getSelfPid
  callRemoteSessionP' nid ($(mkClosure 'spawnSess0) pid)
  expect

test_spawnLLSession :: Process Int
test_spawnLLSession = do
  pid <- getSelfPid
  spawnLLSessionP (sess1' pid) sess2
  expect

test_spawnLRSession :: NodeId -> Process Int
test_spawnLRSession nid = do
  pid <- getSelfPid
  spawnLRSessionP nid ($(mkClosure 'spawnSess0) pid)
  expect

test_spawnRRSession :: NodeId -> Process Int
test_spawnRRSession nid = do
  pid <- getSelfPid
  spawnRRSessionP nid nid ($(mkClosure 'spawnSess0) pid)
  expect