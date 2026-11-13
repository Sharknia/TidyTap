<!--
{
  "availability" : [
    "iOS: 17.0.0 -",
    "iPadOS: 17.0.0 -",
    "macCatalyst: 17.0.0 -",
    "macOS: 14.0.0 -",
    "tvOS: 17.0.0 -",
    "visionOS: -",
    "watchOS: 10.0.0 -"
  ],
  "documentType" : "symbol",
  "framework" : "CloudKit",
  "identifier" : "/documentation/CloudKit/CKSyncEngine-5sie5",
  "metadataVersion" : "0.1.0",
  "role" : "Class",
  "symbol" : {
    "kind" : "Class",
    "modules" : [
      "CloudKit"
    ],
    "preciseIdentifier" : "s:8CloudKit12CKSyncEngineC"
  },
  "title" : "CKSyncEngine"
}
-->

# CKSyncEngine

An object that manages the synchronization of local and remote record data.

```
final class CKSyncEngine
```

## Overview

Use [`CKSyncEngine`](/documentation/CloudKit/CKSyncEngine-5sie5) to handle your app’s CloudKit sync operations and benefit from the performance and reliability it provides.
To use the class, create an instance early in your app’s launch process and specify a database to sync.
Thereafter, and depending on good system conditions, the sync engine periodically pushes and pulls database and record zone changes on the app’s behalf.
To participate in those sync operations and to provide the engine with the changes to send, create a type that conforms to [`CKSyncEngineDelegate`](/documentation/CloudKit/CKSyncEngineDelegate-1q7g8) and assign an instance of it to the engine’s configuration.
You can have multiple instances of [`CKSyncEngine`](/documentation/CloudKit/CKSyncEngine-5sie5) in a single process, each targeting a different database. For example, you may have one syncing a person’s private database and another syncing their shared database.

Because periodic sync relies on good system conditions — adequate battery charge, an active network connection, a signed-in iCloud account, and so on — the engine’s sync schedule is indeterminate.
If you need to sync immediately, like when your app requires it has the most recent changes before continuing, use the [`fetchChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/fetchChanges(_:)) and [`sendChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/sendChanges(_:)) methods.

The sync engine uses an opaque type to track its internal state, and it’s your responsibility to persist that state to disk and make it available across app launches so the engine can function properly.
For more information, see [`handleEvent(_:syncEngine:)`](/documentation/CloudKit/CKSyncEngineDelegate-1q7g8/handleEvent(_:syncEngine:)) and [`CKSyncEngine.Event.StateUpdate`](/documentation/CloudKit/CKSyncEngine-5sie5/Event/StateUpdate).

[`CKSyncEngine`](/documentation/CloudKit/CKSyncEngine-5sie5) requires the CloudKit and Remote notifications entitlements.
For more information, see <doc://com.apple.documentation/documentation/Xcode/configuring-icloud-services> and <doc://com.apple.documentation/documentation/Xcode/configuring-background-execution-modes>.

> Important: Don’t use ``doc://com.apple.cloudkit/documentation/CloudKit/CKSyncEngine-5sie5`` to sync your app’s public database.

### Send changes to iCloud

A sync engine requires you to tell it about any changes to send, which you do by invoking the [`add(pendingDatabaseChanges:)`](/documentation/CloudKit/CKSyncEngine-5sie5/State-swift.class/add(pendingDatabaseChanges:)) and [`add(pendingRecordZoneChanges:)`](/documentation/CloudKit/CKSyncEngine-5sie5/State-swift.class/add(pendingRecordZoneChanges:)) methods on the engine’s [`state`](/documentation/CloudKit/CKSyncEngine-5sie5/state-swift.property) property.
If there are no scheduled sync operations when you invoke these methods, the engine automatically schedules one.
Database changes don’t require any additional input, but the sync engine does expect you to provide the individual record zone changes — in batches — and return them from your delegate’s implementation of [`nextRecordZoneChangeBatch(_:syncEngine:)`](/documentation/CloudKit/CKSyncEngineDelegate-1q7g8/nextRecordZoneChangeBatch(_:syncEngine:)).
After the engine sends the changes, it notifies your delegate about their success (or failure) by dispatching [`CKSyncEngine.Event.sentDatabaseChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/Event/sentDatabaseChanges(_:)) and [`CKSyncEngine.Event.sentRecordZoneChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/Event/sentRecordZoneChanges(_:)) events.

### Batches

The sync engine sends record zone changes to the server in batches, where each batch corresponds to a single network request.
After your app registers pending changes through [`add(pendingRecordZoneChanges:)`](/documentation/CloudKit/CKSyncEngine-5sie5/State-swift.class/add(pendingRecordZoneChanges:)), the engine drives a send operation by repeatedly invoking [`nextRecordZoneChangeBatch(_:syncEngine:)`](/documentation/CloudKit/CKSyncEngineDelegate-1q7g8/nextRecordZoneChangeBatch(_:syncEngine:)) to gather those changes into batches and sending each batch as one request.
It keeps asking for batches until your delegate returns `nil` or the operation is cancelled, meaning a single send operation may span many batches.

Each batch is bounded by the server’s per-request limit of 250 records (saves plus deletes combined); a batch that exceeds the limit fails with [`CKError.Code.limitExceeded`](/documentation/CloudKit/CKError/Code/limitExceeded) and the sync engine treats it like any other send failure.
To stay within the limit automatically, build your batches with [`init(pendingChanges:recordProvider:)`](/documentation/CloudKit/CKSyncEngine-5sie5/RecordZoneChangeBatch/init(pendingChanges:recordProvider:)), which walks your pending changes in order and stops once the batch is full.
Any changes that don’t fit stay in [`pendingRecordZoneChanges`](/documentation/CloudKit/CKSyncEngine-5sie5/State-swift.class/pendingRecordZoneChanges), so the engine picks them up on the next call.

After each batch finishes, the engine dispatches a [`CKSyncEngine.Event.sentRecordZoneChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/Event/sentRecordZoneChanges(_:)) (or [`CKSyncEngine.Event.sentDatabaseChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/Event/sentDatabaseChanges(_:)), for database changes) event that describes only the records in that batch, so a single send operation produces one sent-changes event per batch rather than a single event for the whole operation.

When your delegate builds a batch, include only changes that fall within the scope specified by [`options`](/documentation/CloudKit/CKSyncEngine-5sie5/SendChangesContext/options) on the provided context.
Returning changes outside that scope causes the send to fail with [`invalidArguments`](/documentation/CloudKit/CKError/invalidArguments).

### Fetch changes from iCloud

By default, a sync engine attempts to discover an existing [`CKDatabaseSubscription`](/documentation/CloudKit/CKDatabaseSubscription) for the associated database and uses that to receive silent notifications about remote record changes.
If the engine doesn’t find a subscription, it automatically creates one to use. On receipt of a notification, the engine schedules a sync operation to fetch the related changes.
When that operation runs, the engine dispatches a [`CKSyncEngine.Event.willFetchChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/Event/willFetchChanges(_:)) event to your delegate.
As it receives fetched changes, the engine dispatches [`CKSyncEngine.Event.fetchedDatabaseChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/Event/fetchedDatabaseChanges(_:)) and [`CKSyncEngine.Event.fetchedRecordZoneChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/Event/fetchedRecordZoneChanges(_:)), accordingly.
After the operation finishes, the sync engine notifies your delegate by dispatching a [`CKSyncEngine.Event.didFetchChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/Event/didFetchChanges(_:)) event.
You handle all dispatched events in your delegate’s implementation of [`handleEvent(_:syncEngine:)`](/documentation/CloudKit/CKSyncEngineDelegate-1q7g8/handleEvent(_:syncEngine:)).

### Sync Scheduling

#### Automatic sync

By default, the sync engine automatically schedules sync tasks on your behalf.
If the user is signed in, the device has a network connection, and the system is generally in a good state, these scheduled syncs happen relatively quickly.
However, if the device has no network, is low on power, or is otherwise under a heavy load, these automatic syncs might be delayed.
Similarly, if the user isn’t signed in to an account, the sync engine won’t perform any sync tasks at all.

#### Manual sync

There may be some cases where you want to manually trigger a sync.
For example, if you have a pull-to-refresh UI, you can call [`fetchChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/fetchChanges(_:)) to tell the sync engine to fetch immediately.
Or, if you have a “backup now” UI, you can call [`sendChanges(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/sendChanges(_:)) to send to the server immediately.

### Error Handling

There are some transient errors that the sync engine handles automatically behind the scenes.
The sync engine retries the operations for these transient errors automatically when it makes sense to do so.
Specifically, the sync engine will handle the following errors on your behalf:

- [`CKError.Code.notAuthenticated`](/documentation/CloudKit/CKError/Code/notAuthenticated)
- [`CKError.Code.accountTemporarilyUnavailable`](/documentation/CloudKit/CKError/Code/accountTemporarilyUnavailable)
- [`CKError.Code.networkFailure`](/documentation/CloudKit/CKError/Code/networkFailure)
- [`CKError.Code.networkUnavailable`](/documentation/CloudKit/CKError/Code/networkUnavailable)
- [`CKError.Code.requestRateLimited`](/documentation/CloudKit/CKError/Code/requestRateLimited)
- [`CKError.Code.serviceUnavailable`](/documentation/CloudKit/CKError/Code/serviceUnavailable)
- [`CKError.Code.zoneBusy`](/documentation/CloudKit/CKError/Code/zoneBusy)

When the sync engine encounters one of these errors, it waits for the system to be in a good state, and tries again.
For example, if the server sends back a [`CKError.Code.requestRateLimited`](/documentation/CloudKit/CKError/Code/requestRateLimited) error, the sync engine respects this throttle and tries again after the error’s retry-after time.

`CKSyncEngine` does *not* handle errors that require application-specific logic.
For example, if you try to save a record and get a [`CKError.Code.serverRecordChanged`](/documentation/CloudKit/CKError/Code/serverRecordChanged), you need to handle that error yourself.
There are plenty of errors that the sync engine cannot handle on your behalf, see [`CKError`](/documentation/CloudKit/CKError) for a list of all the possible errors.

### Accounts

`CKSyncEngine` monitors for account status, and it only syncs if there’s an account signed in.
Because of this, you can initialize your `CKSyncEngine` at any time, regardless of account status.
If there is no account, or if the user disabled sync in settings, the sync engine stays dormant in the background.
Once an account is available, the sync engine starts syncing automatically.

The sync engine listens for when the user signs in or out of their account.
When it notices an account change, it sends an [`CKSyncEngine.Event.accountChange(_:)`](/documentation/CloudKit/CKSyncEngine-5sie5/Event/accountChange(_:)) to your delegate.
It’s your responsibility to react appropriately to this change and update your local persistence.

> Tip: A sample code project for ``doc://com.apple.cloudkit/documentation/CloudKit/CKSyncEngine-5sie5`` is available on GitHub here: [CloudKit Samples: CKSyncEngine](https://github.com/apple/sample-cloudkit-sync-engine).

## Topics

### Creating a sync engine

[`init(CKSyncEngine.Configuration)`](/documentation/CloudKit/CKSyncEngine-5sie5/init(_:))

Creates a sync engine with the specified configuration.

[`struct Configuration`](/documentation/CloudKit/CKSyncEngine-5sie5/Configuration)

A type that configures the attributes and behavior of a sync engine.

### Accessing the engine’s attributes

[`var database: CKDatabase`](/documentation/CloudKit/CKSyncEngine-5sie5/database)

The associated database.

[`var state: CKSyncEngine.State`](/documentation/CloudKit/CKSyncEngine-5sie5/state-swift.property)

A collection of state properties used to efficiently manage sync engine operation.

[`class State`](/documentation/CloudKit/CKSyncEngine-5sie5/State-swift.class)

An object that manages the sync engine’s state.

### Participating in scheduled sync operations

[`protocol CKSyncEngineDelegate`](/documentation/CloudKit/CKSyncEngineDelegate-1q7g8)

An interface for providing record data to a sync engine and customizing that engine’s behavior.

### Invoking manual sync operations

[`func fetchChanges(CKSyncEngine.FetchChangesOptions) async throws`](/documentation/CloudKit/CKSyncEngine-5sie5/fetchChanges(_:))

Fetches pending remote changes from the server.

[`struct FetchChangesOptions`](/documentation/CloudKit/CKSyncEngine-5sie5/FetchChangesOptions)

A set of options to use when fetching changes from the server.

[`func sendChanges(CKSyncEngine.SendChangesOptions) async throws`](/documentation/CloudKit/CKSyncEngine-5sie5/sendChanges(_:))

Sends pending local changes to the server.

[`struct SendChangesOptions`](/documentation/CloudKit/CKSyncEngine-5sie5/SendChangesOptions)

A set of options to use when sending changes to the server.

### Canceling operations

[`func cancelOperations() async`](/documentation/CloudKit/CKSyncEngine-5sie5/cancelOperations())

Cancels any in-progress or pending sync operations.

### Debugging the sync engine

[`var description: String`](/documentation/CloudKit/CKSyncEngine-5sie5/description)

The textual description of the engine that’s suitable for logging.

### Structures

[`struct FetchChangesContext`](/documentation/CloudKit/CKSyncEngine-5sie5/FetchChangesContext)

The context of an attempt to fetch changes from the server.

[`struct RecordZoneChangeBatch`](/documentation/CloudKit/CKSyncEngine-5sie5/RecordZoneChangeBatch)

A type that contains the record changes for a single send operation.

[`struct SendChangesContext`](/documentation/CloudKit/CKSyncEngine-5sie5/SendChangesContext)

The context of an attempt to send changes to the server.

### Enumerations

[`enum Event`](/documentation/CloudKit/CKSyncEngine-5sie5/Event)

Describes an event that occurs during a sync operation.

[`enum PendingDatabaseChange`](/documentation/CloudKit/CKSyncEngine-5sie5/PendingDatabaseChange)

Describes an unsent database modification.

[`enum PendingRecordZoneChange`](/documentation/CloudKit/CKSyncEngine-5sie5/PendingRecordZoneChange)

Describes an unsent record modification.

[`enum SyncReason`](/documentation/CloudKit/CKSyncEngine-5sie5/SyncReason)

Describes the reason for a sync operation.

### Default Implementations

[CustomStringConvertible Implementations](/documentation/CloudKit/CKSyncEngine-5sie5/CustomStringConvertible-Implementations)

## Relationships

### Conforms To

[`SendableMetatype`](/documentation/Swift/SendableMetatype)

[`Copyable`](/documentation/Swift/Copyable)

[`CustomStringConvertible`](/documentation/Swift/CustomStringConvertible)

[`Escapable`](/documentation/Swift/Escapable)

[`Sendable`](/documentation/Swift/Sendable)

---

Copyright &copy; 2026 Apple Inc. All rights reserved. | [Terms of Use](https://www.apple.com/legal/internet-services/terms/site.html) | [Privacy Policy](https://www.apple.com/privacy/privacy-policy)