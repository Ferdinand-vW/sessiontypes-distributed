{-# LANGUAGE RebindableSyntax #-}
{-# OPTIONS_GHC -Wno-simplifiable-class-constraints #-}
-- | In this module we lift all functions in "Control.Distributed.Process" that return a function of type Process a to Session s s a.
--
-- Since the functions in this module work identical to the ones in "Control.Distributed.Process" we will refer to that module for documentation.
--
-- There is however some explanation required for functions that take a `Process` as an argument.
--
-- For the functions that also take a Process a as an argument we derive two functions. One that still takes a Process a and one that takes a Session s s a.
--
-- There are also functions that take a Closure (Process ()) as an argument. We cannot lift this to be Closure (Session s s ()) as is explained in "Control.Distributed.Session.Closure".
--
-- To accomodate for this drawback we instead have these functions take a Closure (SessionWrap ()) as an argument.
--
-- Here is an example on how to call `call`.
--
-- @
--
-- {-\# LANGUAGE TemplateHaskell \#-}
-- import qualified SessionTypes.Indexed as I
-- import Control.Distributed.Session (SessionWrap(..), sessionRemoteTable, call, evalSessionEq)
-- import Control.Distributed.Process (liftIO, Process, RemoteTable, NodeId)
-- import Control.Distributed.Process.Serializable (SerializableDict(..))
-- import Control.Distributed.Process.Closure (remotable, mkStaticClosure, mkStatic)
-- import Control.Distributed.Process.Node
-- import Network.Transport.TCP
--
-- sessWrap :: SessionWrap Int
-- sessWrap = SessionWrap $ I.return 5
--
-- sdictInt :: SerializableDict Int
-- sdictInt = SerializableDict
--
-- remotable ['sdictInt, 'sessWrap]
--
-- p1 :: NodeId -> Process ()
-- p1 nid = do
--   a <- evalSessionEq (call $(mkStatic 'sdictInt) nid $(mkStaticClosure 'sessWrap))
--   liftIO $ putStrLn $ show a
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
-- In p1 we run a session that makes a call and then prints out the result of that call.
--
-- Note that this is the call function from "SessionTyped.Distributed.Process.Lifted". It takes a Static (SerializableDict a) and a Closure (SessionWrap a).
--
-- To create a static serializable dictionary we first have to define a function that returns a monomorphic serializable dictionary.
--
-- > sdictInt :: SerializableDict Int
-- > sdictInt = SerializableDict
--
-- We then pass 'sdictInt to remoteable, which is a top-level Template Haskell splice.
--
-- > remoteable ['sdictInt]
--
-- Now we can create a static serializable dictionary with 
--
-- > $(mkStatic 'sdictInt)
--
-- To create a closure for a Session s s we have to wrap it in a `SessionWrap`.
--
-- > sessWrap :: SessionWrap Int
-- > sessWrap = SessionWrap $ I.return 5
-- 
-- Similarly to sdictInt this needs to be a top level definition such that we can use Template Haskell to derive a Closure 
--
-- > remotable ['sdictInt, 'sessWrap]
-- > $(mkStaticClosure 'sessWrap)
--
-- Since `call` makes use of internally defined closures, you also have to include `sessionRemoteTable`. 
--
-- > myRemoteTable = Main.__remoteTable $ sessionRemoteTable initRemoteTable
--
-- The remote tables contains a mapping from labels to evaluation functions that a node uses to evaluate closures.
-- 
-- > node <- newLocalNode t myRemoteTable
--  
--  
module Control.Distributed.Session.Lifted (
  utsend,
  usend,
  expect,
  expectTimeout,
  newChan,
  sendChan,
  receiveChan,
  receiveChanTimeout,
  mergePortsBiased,
  mergePortsRR,
  unsafeSend,
  unsafeSendChan,
  unsafeNSend,
  unsafeNSendRemote,
  receiveWait,
  receiveTimeout,
  unwrapMessage,
  handleMessage,
  handleMessage_,
  handleMessageP,
  handleMessageP_,
  handleMessageIf,
  handleMessageIf_,
  handleMessageIfP,
  handleMessageIfP_,
  forward,
  uforward,
  delegate,
  relay,
  proxy,
  proxyP,
  spawn,
  spawnP,
  call,
  callP,
  terminate,
  die,
  kill,
  exit,
  catchExit,
  catchExitP,
  catchesExit,
  catchesExitP,
  getSelfPid,
  getSelfNode,
  getOthPid,
  getOthNode,
  getProcessInfo,
  getNodeStats,
  link,
  linkNode,
  unlink,
  unlinkNode,
  monitor,
  monitorNode,
  monitorPort,
  unmonitor,
  withMonitor,
  withMonitor_,
  withMonitorP,
  withMonitorP_,
  unStatic,
  unClosure,
  say,
  register,
  unregister,
  whereis,
  nsend,
  registerRemoteAsync,
  reregisterRemoteAsync,
  whereisRemoteAsync,
  nsendRemote,
  spawnAsync,
  spawnAsyncP,
  spawnSupervised,
  spawnSupervisedP,
  spawnLink,
  spawnLinkP,
  spawnMonitor,
  spawnMonitorP,
  spawnChannel,
  spawnChannelP,
  spawnLocal,
  spawnLocalP,
  spawnChannelLocal,
  spawnChannelLocalP,
  callLocal,
  callLocalP,
  reconnect,
  reconnectPort
) where

import qualified Control.Distributed.Process as P
import           Control.Distributed.Process.Serializable
import           Control.Distributed.Session.Session
import           Control.Distributed.Session.Closure
import           Control.Distributed.Session.Eval
import           Control.SessionTypes.Indexed
import           Data.Typeable (Typeable)
import qualified Prelude as PL

-- | Unsession typed send
utsend :: Serializable a => P.ProcessId -> a -> Session s s ()
utsend pid a = liftP $ P.send pid a

-- | Unsafe send
usend :: Serializable a => P.ProcessId -> a -> Session s s ()
usend pid a = liftP $ P.usend pid a

expect :: Serializable a => Session s s a
expect = liftP P.expect

expectTimeout :: Serializable a => Int -> Session s s (Maybe a)
expectTimeout = liftP . P.expectTimeout

newChan :: Serializable a => Session s s (P.SendPort a, P.ReceivePort a)
newChan = liftP P.newChan

sendChan :: Serializable a => P.SendPort a -> a -> Session s s ()
sendChan sp a = liftP $ P.sendChan sp a

receiveChan :: Serializable a => P.ReceivePort a -> Session s s a
receiveChan = liftP . P.receiveChan

receiveChanTimeout :: Serializable a => Int -> P.ReceivePort a -> Session s s (Maybe a)
receiveChanTimeout n rp = liftP $ P.receiveChanTimeout n rp

mergePortsBiased :: Serializable a => [P.ReceivePort a] -> Session s s (P.ReceivePort a)
mergePortsBiased = liftP . P.mergePortsBiased

mergePortsRR :: Serializable a => [P.ReceivePort a] -> Session s s (P.ReceivePort a)
mergePortsRR = liftP . P.mergePortsRR

unsafeSend :: Serializable a => P.ProcessId -> a -> Session s s ()
unsafeSend pid a = liftP $ P.unsafeSend pid a

unsafeUSend :: Serializable a => P.ProcessId -> a -> Session s s ()
unsafeUSend pid a = liftP $ P.unsafeUSend pid a

unsafeSendChan :: Serializable a => P.SendPort a -> a -> Session s s ()
unsafeSendChan pid a = liftP $ P.unsafeSendChan pid a

unsafeNSend :: Serializable a => String -> a -> Session s s ()
unsafeNSend s a = liftP $ P.unsafeNSend s a

unsafeNSendRemote :: Serializable a => P.NodeId -> String -> a -> Session s s ()
unsafeNSendRemote n s a = liftP $ P.unsafeNSendRemote n s a

receiveWait :: [P.Match b] -> Session s s b
receiveWait = liftP . P.receiveWait

receiveTimeout :: Int -> [P.Match b] -> Session s s (Maybe b)
receiveTimeout n ms = liftP $ P.receiveTimeout n ms

unwrapMessage :: Serializable a => P.Message -> Session s s (Maybe a)
unwrapMessage = liftP . P.unwrapMessage

handleMessage :: Serializable a => P.Message -> (a -> Session s s b) -> Session r r (Maybe b)
handleMessage m f = handleMessageP m $ \a -> evalSessionEq (f a)

handleMessageP :: Serializable a => P.Message -> (a -> P.Process b) -> Session s s (Maybe b)
handleMessageP m f = liftP $ P.handleMessage m f

handleMessageIf :: Serializable a => P.Message -> (a -> Bool) -> (a -> Session s s b) -> Session r r (Maybe b)
handleMessageIf m f g = handleMessageIfP m f $ \a -> evalSessionEq (g a)

handleMessageIfP :: Serializable a => P.Message -> (a -> Bool) -> (a -> P.Process b) -> Session s s (Maybe b)
handleMessageIfP m f g = liftP $ P.handleMessageIf m f g

handleMessage_ :: Serializable a => P.Message -> (a -> Session s s ()) -> Session r r ()
handleMessage_ m f = handleMessageP_ m $ \a -> evalSessionEq (f a)

handleMessageP_ :: Serializable a => P.Message -> (a -> P.Process ()) -> Session s s ()
handleMessageP_ m f = liftP $ P.handleMessage_ m f

handleMessageIf_ :: Serializable a => P.Message -> (a -> Bool) -> (a -> Session s s ()) -> Session r r ()
handleMessageIf_ m f g = handleMessageIfP_ m f (\a -> evalSessionEq (g a))

handleMessageIfP_ :: Serializable a => P.Message -> (a -> Bool) -> (a -> P.Process ()) -> Session s s ()
handleMessageIfP_ m f g = liftP $ P.handleMessageIf_ m f g

forward :: P.Message -> P.ProcessId -> Session s s ()
forward m pid = liftP $ P.forward m pid

uforward :: P.Message -> P.ProcessId -> Session s s ()
uforward m pid = liftP $ P.uforward m pid

delegate :: P.ProcessId -> (P.Message -> Bool) -> Session s s ()
delegate pid f = liftP $ P.delegate pid f

relay :: P.ProcessId -> Session s s ()
relay = liftP . P.relay

proxy :: Serializable a => P.ProcessId -> (a -> Session s s Bool) -> Session r r ()
proxy pid f = proxyP pid $ \a -> evalSessionEq (f a)

proxyP :: Serializable a => P.ProcessId -> (a -> P.Process Bool) -> Session s s ()
proxyP pid f = liftP $ P.proxy pid f

spawn :: P.NodeId -> P.Closure (SessionWrap ()) -> Session s s P.ProcessId
spawn n proc = do
  spawnP n $ remoteSessionClosure' proc

spawnP :: P.NodeId -> P.Closure (P.Process ()) -> Session s s P.ProcessId
spawnP n proc = liftP $ P.spawn n proc

call :: Serializable a => P.Static (SerializableDict a) -> P.NodeId -> P.Closure (SessionWrap a) -> Session r r a
call dict n proc = callP dict n $ remoteSessionClosure dict proc

callP :: Serializable a => P.Static (SerializableDict a) -> P.NodeId -> P.Closure (P.Process a) -> Session s s a
callP dict n proc = liftP $ P.call dict n proc

terminate :: Session s s a
terminate = liftP P.terminate

die :: Serializable a => a -> Session s s b
die = liftP . P.die

kill :: P.ProcessId -> String -> Session s s ()
kill pid s = liftP $ P.kill pid s

exit :: Serializable a => P.ProcessId -> a -> Session s s ()
exit pid a = liftP $ P.exit pid a

catchExit :: (Show a, Serializable a) => Session s s b -> (P.ProcessId -> a -> Session r r b) -> Session t t b
catchExit sess f = do
  let prod = evalSessionEq sess
  let pf = \pid a -> evalSessionEq (f pid a)
  catchExitP prod pf

catchExitP :: (Show a, Serializable a) => P.Process b -> (P.ProcessId -> a -> P.Process b) -> Session s s b
catchExitP p f = liftP $ P.catchExit p f

catchesExit :: Session s s b -> [P.ProcessId -> P.Message -> Session r r (Maybe b)] -> Session t t b
catchesExit sess xs = do
  let prod = evalSessionEq sess
  let xsp = map (\f -> \pid m -> evalSessionEq (f pid m)) xs
  catchesExitP prod xsp 

catchesExitP :: P.Process b -> [P.ProcessId -> P.Message -> P.Process (Maybe b)] -> Session s s b
catchesExitP p xs = liftP $ P.catchesExit p xs

getSelfPid :: Session s s P.ProcessId
getSelfPid = liftP P.getSelfPid

getSelfNode :: Session s s P.NodeId
getSelfNode = liftP P.getSelfNode

getOthPid :: Session s s (Maybe P.ProcessId)
getOthPid = Session $ \si -> return $ PL.fmap othPid si

getOthNode :: Session s s (Maybe P.NodeId)
getOthNode = Session $ \si -> return $ PL.fmap othNode si

getProcessInfo :: P.ProcessId -> Session s s (Maybe P.ProcessInfo)
getProcessInfo = liftP . P.getProcessInfo

getNodeStats :: P.NodeId -> Session s s (Either P.DiedReason P.NodeStats)
getNodeStats = liftP . P.getNodeStats

link :: P.ProcessId -> Session s s ()
link = liftP . P.link

linkNode :: P.NodeId -> Session s s ()
linkNode = liftP . P.linkNode

linkPort :: P.SendPort a -> Session s s ()
linkPort = liftP . P.linkPort

unlink :: P.ProcessId -> Session s s ()
unlink = liftP . P.unlink

unlinkNode :: P.NodeId -> Session s s ()
unlinkNode = liftP . P.unlinkNode

unlinkPort :: P.SendPort a -> Session s s ()
unlinkPort = liftP . P.unlinkPort

monitor :: P.ProcessId -> Session s s P.MonitorRef
monitor = liftP . P.monitor

monitorNode :: P.NodeId -> Session s s P.MonitorRef
monitorNode = liftP . P.monitorNode

monitorPort :: Serializable a => P.SendPort a -> Session s s P.MonitorRef
monitorPort = liftP . P.monitorPort

unmonitor :: P.MonitorRef -> Session s s ()
unmonitor = liftP . P.unmonitor

withMonitor :: P.ProcessId -> (P.MonitorRef -> Session s s a) -> Session r r a
withMonitor pid f = withMonitorP pid $ \ref -> evalSessionEq (f ref)

withMonitorP :: P.ProcessId -> (P.MonitorRef -> P.Process a) -> Session s s a
withMonitorP pid f = liftP $ P.withMonitor pid f

withMonitor_ :: P.ProcessId -> Session s s a -> Session r r a
withMonitor_ pid sess = withMonitorP_ pid $ evalSessionEq sess

withMonitorP_ :: P.ProcessId -> P.Process a -> Session s s a
withMonitorP_ pid p = liftP $ P.withMonitor_ pid p

unStatic :: Typeable a => P.Static a -> Session s s a
unStatic = liftP . P.unStatic

unClosure :: Typeable a => P.Closure a -> Session s s a
unClosure = liftP . P.unClosure

say :: String -> Session s s ()
say = liftP . P.say

register :: String -> P.ProcessId -> Session s s ()
register s pid = liftP $ P.register s pid

unregister :: String -> Session s s ()
unregister = liftP . P.unregister

whereis :: String -> Session s s (Maybe P.ProcessId)
whereis = liftP . P.whereis

nsend :: Serializable a => String -> a -> Session s s ()
nsend s a = liftP $ P.nsend s a

registerRemoteAsync :: P.NodeId -> String -> P.ProcessId -> Session s s ()
registerRemoteAsync node s pid = liftP $ P.registerRemoteAsync node s pid

reregisterRemoteAsync :: P.NodeId -> String -> P.ProcessId -> Session s s ()
reregisterRemoteAsync node s pid = liftP $ P.reregisterRemoteAsync node s pid

unregisterRemoteAsync :: P.NodeId -> String -> Session s s ()
unregisterRemoteAsync node s = liftP $ P.unregisterRemoteAsync node s

whereisRemoteAsync :: P.NodeId -> String -> Session s s ()
whereisRemoteAsync node s = liftP $ P.whereisRemoteAsync node s

nsendRemote :: Serializable a => P.NodeId -> String -> a -> Session s s ()
nsendRemote node s a = liftP $ P.nsendRemote node s a

spawnAsync :: P.NodeId -> P.Closure (SessionWrap ()) -> Session r r P.SpawnRef
spawnAsync n proc = spawnAsyncP n $ remoteSessionClosure' proc

spawnAsyncP :: P.NodeId -> P.Closure (P.Process ()) -> Session s s P.SpawnRef
spawnAsyncP n proc =  liftP $ P.spawnAsync n proc

spawnSupervised :: P.NodeId -> P.Closure (SessionWrap ()) -> Session s s (P.ProcessId, P.MonitorRef)
spawnSupervised n proc = spawnSupervisedP n $ remoteSessionClosure' proc

spawnSupervisedP :: P.NodeId -> P.Closure (P.Process ()) -> Session s s (P.ProcessId, P.MonitorRef)
spawnSupervisedP n proc = liftP $ P.spawnSupervised n proc

spawnLink :: P.NodeId -> P.Closure (SessionWrap ()) -> Session s s P.ProcessId
spawnLink n proc = spawnLinkP n $ remoteSessionClosure' proc

spawnLinkP :: P.NodeId -> P.Closure (P.Process ()) -> Session s s P.ProcessId
spawnLinkP n proc = liftP $ P.spawnLink n proc

spawnMonitor :: P.NodeId -> P.Closure (SessionWrap ()) -> Session s s (P.ProcessId, P.MonitorRef)
spawnMonitor n proc = spawnMonitorP n $ remoteSessionClosure' proc

spawnMonitorP :: P.NodeId -> P.Closure (P.Process ()) -> Session s s (P.ProcessId, P.MonitorRef)
spawnMonitorP n proc = liftP $ P.spawnMonitor n proc

spawnChannel :: Serializable a => P.Static (SerializableDict a) -> P.NodeId -> P.Closure (P.ReceivePort a -> SessionWrap ()) -> Session s s (P.SendPort a)
spawnChannel st n proc = spawnChannelP st n $ spawnChannelClosure st proc

spawnChannelP :: Serializable a => P.Static (SerializableDict a) -> P.NodeId -> P.Closure (P.ReceivePort a -> P.Process ()) -> Session s s (P.SendPort a)
spawnChannelP st n proc = liftP $ P.spawnChannel st n proc

spawnLocal :: Session s s () -> Session r r P.ProcessId
spawnLocal sess = spawnLocalP $ evalSessionEq sess

spawnLocalP :: P.Process () -> Session s s P.ProcessId
spawnLocalP = liftP . P.spawnLocal

spawnChannelLocal :: Serializable a => (P.ReceivePort a -> Session s s ()) -> Session r r (P.SendPort a)
spawnChannelLocal f = spawnChannelLocalP $ evalSessionEq . f

spawnChannelLocalP :: Serializable a => (P.ReceivePort a -> P.Process ()) -> Session s s (P.SendPort a)
spawnChannelLocalP = liftP . P.spawnChannelLocal

callLocal :: Session s s a -> Session s s a
callLocal sess = callLocalP $ evalSessionEq sess

callLocalP :: P.Process a -> Session s s a
callLocalP = liftP . P.callLocal

reconnect :: P.ProcessId -> Session s s ()
reconnect = liftP . P.reconnect

reconnectPort :: P.SendPort a -> Session s s ()
reconnectPort = liftP . P.reconnectPort