# Introduction

This package serves as a wrapper over both the Cloud Haskell library (distributed-process) and the sessiontypes library.
It provides an interpreter for evaluating session typed programs to Cloud Haskell programs and exposes several combinators for spawning sessions.

# Install

Add `sessiontypes-distributed` as a dependency in your `.cabal` file

# Tutorial

Before reading this you should first read the [sessiontypes](https://github.com/Ferdinand-vW/sessiontypes) tutorial, which explains session types and what happens under the hood of this library. We also assume that you're already familiar with the [distributed-process](http://haskell-distributed.github.io/) library.

Similar to that tutorial we will start off by writing a simple session typed program:

```haskell
{-# LANGUAGE RebindableSyntax #-}
import Control.Distributed.Session
import Control.SessionTypes.Indexed

prog :: Session ('Cap '[] (Int :!> String :?> Eps)) ('Cap '[] Eps) String
prog = do
  send 5
  x <- recv
  eps x
```

The program is written quite similarly to an equivalent `STTerm` program. We now use an indexed monad named `Session`. It is parameterised similarly, except that it isn't a monad transformer. The `Session` monad is an indexed monad reader and a wrapper over the `STTerm` monad that has the `Process` monad (from distributed-process) as its underlying monad.

One of the features that this library provides above sessiontypes is that we can evaluate a `Session` to a `Process`:

```haskell
evalSession :: HasConstraint Serializable s => Session s r a -> SessionInfo -> P.Process a
```

This function takes not only a `Session`, but also a `SessionInfo`. The `SessionInfo` contains information about the dual of the given `Session`. That is the process that the current process should run in a session with. The `SessionInfo` stores the process and node identifier of that process, but it also stores a send and receive port that it can use to send and receive messages.
To send and receive a message the value that will be sent must be serializable. However, the type of that value is encoded in the session type and we can't easily reach it. For that purpose we defined a type family `HasConstraint` that applies a given constraint to all types of kind `Type` in the session type.

The ability to write a session typed program and evaluate it terms of Cloud Haskell semantics only gives us a static guarantee that this specific program adheres to the given protocol. We would also like there to be another program that runs a session with this program and have it adhere to the dual of that protocol. First we will define duality.

```haskell
type family Dual s = r | r -> s where
  Dual (a :!> r) = a :?> Dual r
  Dual (a :?> r) = a :!> Dual r
  Dual Eps = Eps
```

We can compute the dual of a session type using the type family `Dual`. For a send the dual is a receive and the dual of a receive is a send. If one program does a send then we expect the dual of that program to do a receive. Likewise, if one program ends the protocol then so should the dual of that program. Duality is a nice property to have, because it allows us to statically enforce that two programs in a session do not deadlock.

The following combinator can be used to spawn a session:

```haskell
callLocalSession :: (HasConstraint Serializable s,
                     HasConstraint Serializable (Dual s)) =>
                     Session s r a -> Session (Dual s) r b -> Session k k (a, ProcessId)
```
It takes two `Session` arguments and we use `Dual` to say that the second `Session` must be the dual of the first. The function works similar to the `call` function in distributed-process. It spawns a local process for the second `Session`, but runs the first `Session` on the current process and waits for its result. The returned `ProcessId` is that of the spawned process.

A similar combinator for spawning a session is `callRemoteSession`. This time the second `Session` will be spawned on a remote node. But to do so we have to create a closure of that `Session`. Unfortunately, this cannot easily be done. The types that occur in a `Closure` must be of kind `Type`. However, the indexed of a `Session` are of kind `Cap`. So we can't construct a closure of a `Session`. We managed to work around this problem by defining a GADT that existentially quantifies the indexes of a `Session`. But we must still be able to enforce duality and apply constraints to the session types. We therefore require that the GADT takes two `Session` arguments, enforces that these must be dual and applies a `Serializable` constraint to the session types.

```haskell
data SpawnSession a b where
  SpawnSession :: (HasConstraint Serializable s, HasConstraint Serializable (Dual s)) => 
                  Session s r a -> Session (Dual s) r b -> SpawnSession a b

callRemoteSession :: Serializable a => Static (SerializableDict a) -> NodeId -> Closure (SpawnSession a ()) -> Session k k (a, ProcessId)
```
We can now also show you the type of `callRemoteSession` that takes a closure of a `SpawnSession`. Note that if you make use of any function that takes a closure that requires a data type from this library then you will need to use `sessionRemoteTable`.
