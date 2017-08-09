//
//  main.swift
//  cloudkit
//
//  Created by Rahul Thukral on 09/08/17.
//  Copyright © 2017 Rahul Thukral. All rights reserved.
//





/*   # CloudKit Share: Using CloudKit share APIs

***********************RAHUL THUKRAL****************************

## Description



This sample demonstrates how to use CloudKit share APIs to share private data across different iCloud accounts. It also shows how to use CloudKit querys and subscriptions to maintain a local cache of CloudKit data. This is an important topic because almost every CloudKit request goes through the network, which may not always be in a good situation. Having a local cache can dramatically improve the usage and UI responsiveness of an app. This sample also provides a pattern of error handling and asynchronous programming when working with CloudKit, and covers permission management and conflict handling while editing a record.





### Schema



This sample requires two record types, Topic and Notes. You can create them by opening CloudKit Dashboard in Safari (https://icloud.developer.apple.com/dashboard/), picking the iCloud container you are going to use, and adding the following record types and fields:



Topic

name:   String

Note

title:  String

topic:  Reference



Be sure to check the "Sort", "Query", and "Search" box since CloudKit Share does a lot of fetches on the data.



Note that CloudKit errors will be triggered if the schema doesn't exist in your iCloud container, so make sure to set up your schema before running the sample. After creating the schema, you might need to wait a few minutes for CloudKit servers to finish the synchronization.



## Setup



1. Open the project file of this sample (CloudShares.xcodeproj) with the latest version of Xcode.



2. In the project editor, change the bundle identifier under Identity on the General pane. The bundle identifier is used to create the app’s default container.



3. In the Capabilities pane, make sure that iCloud is on and the CloudKit option is checked. The project is set to use the default container. If you specify a custom container here, you need to change the line of code in AppDelegate.swift to create the CKContainer object with your custom container identifier.



4. Make sure your testing devices run the latest iOS and are signed in with iCloud accounts. This sample doesn't work on iOS Simulators because iOS Simulators don't support notifications.



5. Before being able to play with the "Share" button, you need to create a custom zone in the private database, and put some records in it. Only custom zone records can be shared.





## Requirements



### Build



Latest iOS (iOS 10.2 or later) SDK ; Xcode 8.2 or later



### Runtime



iOS 10.1 or later



Copyright (C) 2017 Rahul Thukral . All rights reserved.*/
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 A class to handle CloudKit errors.
 
 */



import UIKit

import CloudKit



// Due to the asynchronous nature of the CloudKit framework. Every API that needs to reach to the server

// can fail (for networking issue, for example).

// This class is to handle errors as much as possible based on the operation type, or preprocess the error data

// and pass back to caller for further actions.

//

class CloudKitError {



// Operation types that identifying what is doing.

//

enum Operation: String {

case accountStatus = "AccountStatus"// Doing account check with CKContainer.accountStatus.

case fetchRecords = "FetchRecords"  // Fetching data from the CloudKit server.

case modifyRecords = "ModifyRecords"// Modifying records (.serverRecordChanged should be handled).

case deleteRecords = "DeleteRecords"// Deleting records.

case modifyZones = "ModifyZones"    // Modifying zones (.serverRecordChanged should be handled).

case deleteZones = "DeleteZones"    // Deleting zones.

case fetchZones = "FetchZones"      // Fetching zones.

case modifySubscriptions = "ModifySubscriptions"    // Modifying subscriptions.

case deleteSubscriptions = "DeleteSubscriptions"    // Deleting subscriptions.

case fetchChanges = "FetchChanges"  // Fetching changes (.changeTokenExpired should be handled).

case markRead = "MarkRead"          // Doing CKMarkNotificationsReadOperation.

case acceptShare = "AcceptShare"    // Doing CKAcceptSharesOperation.

}



// Dictioanry keys for error handling result that would be returned to clients.

//

enum Result {

case ckError, nsError

}



static let share = CloudKitError()

private init() {} // Prevent clients from creating another instance.



lazy var operationQueue: OperationQueue = {

let queue = OperationQueue()

queue.maxConcurrentOperationCount = 1

return queue

}()



// Error handling: partial failure caused by .serverRecordChanged can normally be ignored.

// the CKError is returned so clients can retrieve more information from there.

//

// Return the ckError when the first partial error is hit, so only handle the first error.

// Return nil if the error is not handled.

//

fileprivate func handlePartialError(nsError: NSError, affectedObjects: [Any]?) -> CKError? {



guard let partialErrorInfo = nsError.userInfo[CKPartialErrorsByItemIDKey] as? NSDictionary,

let editingObjects = affectedObjects else {return nil}



for editingObject in editingObjects {



guard let ckError = partialErrorInfo[editingObject] as? CKError else {continue}



if ckError.code == .serverRecordChanged {

print("Editing object already exists. Normally use serverRecord and ignore this error!")

}

else if ckError.code == .zoneNotFound {

print("Zone not found. Normally switch the other zone!")

}

else if ckError.code == .unknownItem {

print("Items not found, which happens in the cloud environment. Probably ignore!")

}

else if ckError.code == .batchRequestFailed {

print("Atomic failure!")

}

return ckError

}

return nil

}



// Return nil: no error or the error is ignorable.

// Return a Dictionary: return the preprocessed data so caller can choose to do something.

//

func handle(error: Error?, operation: Operation, affectedObjects: [Any]? = nil, alert: Bool = false) -> [Result: Any]? {



// nsError == nil: Everything goes well, callers can continue.

//

guard let nsError = error as NSError? else { return nil}



// Partial errors can happen when fetching or changing the database.

// In the case of modifying zones, records, and subscription:

// .serverRecordChanged: retrieve the first CKError object and return for callers to use ckError.serverRecord.

//

// In the case of .fetchRecords and fetchChanges:

// the specified items (.unknownItem) or zone (.zoneNotFound)

// may not be found in database. We just ignore this kind of errors.

//

if let ckError = handlePartialError(nsError: nsError, affectedObjects: affectedObjects) {



// Items not found. Ignore for the delete operation.

//

if operation == .deleteZones || operation == .deleteRecords || operation == .deleteSubscriptions {

if ckError.code == .unknownItem {

return nil

}

}

return [Result.ckError: ckError]

}



// In the case of fetching changes:

// .changeTokenExpired: return for callers to refetch with nil server token.

// .zoneNotFound: return for callers to switch zone, as the current zone has been deleted.

// .partialFailure: zoneNotFound will trigger a partial error as well.

//

if operation == .fetchChanges {

if let ckError = error as? CKError {

if ckError.code == .changeTokenExpired || ckError.code == .zoneNotFound {

return [Result.ckError: ckError]

}

}

}



// .markRead: we don't care the errors occuring when marking read as we can do that next time,

// so return nil to continue the flow.

//

if operation == .markRead {

return nil

}



// For other errors, simply log it if:

// 1. clients doen't want an alert.

// 2. clients want an alert but there is already an alert in the queue.

//    We only present the first alert in this case, so simply return.

//

if alert == false || operationQueue.operationCount > 0 {

print("!!!!!\(operation.rawValue) operation error: \(nsError)")

return [Result.nsError: nsError]

}



// Present alert if necessary.

//

operationQueue.addOperation {

guard let window = UIApplication.shared.delegate?.window, let vc = window?.rootViewController

else {return}



var isAlerting = true



DispatchQueue.main.async {

let alert = UIAlertController(title: "Unhandled error during \(operation.rawValue) operation.",

message: "\(nsError)",

preferredStyle: .alert)

alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default) { _ in

isAlerting = false

})

vc.present(alert, animated: true)

}



// Wait until the alert is dismissed by the user tapping on the OK button.

//

while isAlerting {

RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))

}

}

return [Result.nsError: nsError]

}

}


/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 View controller class for managing zones.
 
 */



import UIKit

import CloudKit



extension Notification.Name {

static let zoneDidChange = Notification.Name("zoneDidChange")

}



// ZoneViewController: present the zones in current iCloud container and manages zone deletion / creation.

// Conflict handling:

// Adding: add a new zone anyway so no conflict has to be considered

//

// Deleting: the zone to be deleted can be changed or deleted. In that case, CloudKit should return

// .zoneNotFound for .itemNotFound, which will be ignored in a deletion operation.

//

// So no conflicting handling is needed here.

//

class ZoneViewController: SpinnerViewController {



override func viewDidLoad() {

super.viewDidLoad()



navigationItem.rightBarButtonItem = editButtonItem

clearsSelectionOnViewWillAppear = false



NotificationCenter.default.addObserver(self,

selector: #selector(type(of:self).zoneCacheDidChange(_:)),

name: NSNotification.Name.zoneCacheDidChange,

object: nil)

// Start spinner animation.

// ZoneCacheDidChange should come soon, which will stop the animation

// if the local cache container is not ready, notification won't come though.

//

if ZoneLocalCache.share.container != nil {

spinner.startAnimating()

}

}



override func viewWillAppear(_ animated: Bool) {



super.viewWillAppear(animated)

guard ZoneLocalCache.share.container != nil else {return}



// Set the tableview selected row based on the current ZoneLocalCache.

//

selectTableRow(with: TopicLocalCache.share.zone, database: TopicLocalCache.share.database)

}



deinit {

NotificationCenter.default.removeObserver(self)

}



override func setEditing(_ editing: Bool, animated: Bool) {



super.setEditing(editing, animated: animated)



UIView.transition(with: tableView, duration: 0.4, options: .transitionCrossDissolve,

animations: {self.tableView.reloadData()})

}



@IBAction func toggleZone(_ sender: AnyObject) {



let menuViewController = view.window?.rootViewController as! MenuViewController

menuViewController.toggleMenu()

}

}



// Actions and handlers.

//

extension ZoneViewController {



// Notification is posted from main thread by cache class.

//

func zoneCacheDidChange(_ notification: Notification) {



spinner.stopAnimating()



// tableView.numberOfSections can be 0 when the app is entering foreground and the

// account is unavaible. Simply reloadData in this case.

//

if tableView.numberOfSections > 0 {



var sections = [Int]()

for (index, database) in ZoneLocalCache.share.databases.enumerated()

where database.cloudKitDB.databaseScope != .public {

sections.append(index)

}

tableView.reloadSections(IndexSet(sections), with: .automatic)

}

else {

tableView.reloadData()

}

selectTableRow(with: TopicLocalCache.share.zone, database: TopicLocalCache.share.database)

}



// Present an alert controller and add a new record zone with the specified name if users choose to do that.

//

func addZone(at section: Int) {



let alert = UIAlertController(title: "New Zone.", message: "Creating a new zone.", preferredStyle: .alert)

alert.addTextField() { textField -> Void in textField.placeholder = "Name" }

alert.addAction(UIAlertAction(title: "New Zone", style: .default) {_ in



guard let zoneName = alert.textFields![0].text, zoneName.isEmpty == false else {return}



self.spinner.startAnimating()

let database = ZoneLocalCache.share.databases[section]

ZoneLocalCache.share.saveZone(with: zoneName, ownerName: CKCurrentUserDefaultName, to: database)

})

alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.default, handler: nil))

present(alert, animated: true, completion: nil)

}



// Select the row when zone is changed from outside this view controller.

//

func selectTableRow(with zone: CKRecordZone, database: CKDatabase) {



if let section = ZoneLocalCache.share.databases.index(where: {$0.cloudKitDB === database}),

let row = ZoneLocalCache.share.databases[section].zones.index(where: {$0.zoneID == zone.zoneID}) {



let indexPath = IndexPath(row: row, section: section)

tableView.selectRow(at: indexPath, animated: false, scrollPosition: .middle)

}

}

}



// Extension for UITableViewDataSource and UITableViewDelegate.

//

extension ZoneViewController {



override func numberOfSections(in tableView: UITableView) -> Int {



guard ZoneLocalCache.share.container != nil else {return 0}

return ZoneLocalCache.share.databases.count

}



override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {

return ZoneLocalCache.share.databases[section].name

}



override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {



guard ZoneLocalCache.share.container != nil else {return 0}



if ZoneLocalCache.share.databases[section].cloudKitDB.databaseScope == .private {



if isEditing {

return ZoneLocalCache.share.databases[section].zones.count + 1

}

}

return ZoneLocalCache.share.databases[section].zones.count

}



override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {



let cell = tableView.dequeueReusableCell(withIdentifier: TableCellReusableID.subTitle,

for: indexPath)



let database = ZoneLocalCache.share.databases[indexPath.section]



if indexPath.row == database.zones.count {

cell.textLabel?.text = "Add a zone"

}

else {

let zone = ZoneLocalCache.share.databases[indexPath.section].zones[indexPath.row]

cell.textLabel?.text = zone.zoneID.zoneName

}

cell.detailTextLabel?.text = ""

return cell

}



override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {



let database = ZoneLocalCache.share.databases[indexPath.section]



if database.zones.count > indexPath.row {

if database.zones[indexPath.row].zoneID.zoneName == CKRecordZoneDefaultName {

return false

}

}

return true

}



override func tableView(_ tableView: UITableView,

editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {



let database = ZoneLocalCache.share.databases[indexPath.section]

return (database.zones.count == indexPath.row) ? .insert : .delete

}



override func tableView(_ tableView: UITableView,

shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {

return false

}



override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle,

forRowAt indexPath: IndexPath) {



guard !ZoneLocalCache.share.isUpdating() else {alertCacheUpdating(); return}



// Adding a zone doesn't have any race condition because the database is always there and/

// the zone will be new.

//

if editingStyle == .insert {

addZone(at: indexPath.section)

return

}



// Theoritically there is a race condition here: database.zones[indexPath.row] may not be the same as the one

// picked from the UI. The reason is that the cache can be changed in the interval between the moment of

// picking and the moment of getting the item. However, with the above guard, it is safe to

// say that cahce changing (meaning notification -> cloudkit operations -> cache changing) can't happen in

// this short interval.

//

let database = ZoneLocalCache.share.databases[indexPath.section]

let zone = database.zones[indexPath.row]



spinner.startAnimating()



// If the current zone is being deleted, switch the default zone of the private db first

// to make sure the subscritions of the current zone are deleted.

//

if TopicLocalCache.share.database === database.cloudKitDB && TopicLocalCache.share.zone == zone {

TopicLocalCache.share.switchZone(newDatabase: TopicLocalCache.share.container.privateCloudDatabase,

newZone: CKRecordZone.default())

}

ZoneLocalCache.share.deleteZone(zone, from: database)

}



override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {



// Refresh the cache even the selected row is the current row

// This is to provide a way to refresh the cache of the current zone.



let menuViewController = view.window?.rootViewController as! MenuViewController



if let mainNC = menuViewController.mainViewController as? UINavigationController,

let mainVC = mainNC.topViewController as? MainViewController {

mainVC.view.bringSubview(toFront: mainVC.spinner)

mainVC.spinner.startAnimating()

}

DispatchQueue.global().async {

let database = ZoneLocalCache.share.databases[indexPath.section]

TopicLocalCache.share.switchZone(newDatabase: database.cloudKitDB,

newZone: database.zones[indexPath.row])

}

menuViewController.toggleMenu() // Hide the zone view.

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 Table view cell class for text input.
 
 */



import UIKit

import CloudKit



// Use object + property, rather than a simple value property, as the data model.

//

class TableViewTextFieldCell: UITableViewCell, UITextFieldDelegate {



@IBOutlet weak var titleLabel: UILabel!

@IBOutlet weak var textField: UITextField!



var object: CKRecord? {

didSet {

guard let record = object, let propertyName = propertyName else {return}

textField.text = record[propertyName] as? String

}

}



var propertyName: String? {

didSet {

guard let record = object, let propertyName = propertyName else {return}

textField.text = record[propertyName] as? String

}

}



override func awakeFromNib() {

super.awakeFromNib()

textField.delegate = self

textField.isEnabled = false

}



override func setEditing(_ editing: Bool, animated: Bool) {

super.setEditing(editing, animated: animated)

textField.isEnabled = editing

}



func textFieldShouldReturn(_ textField: UITextField) -> Bool {

textField.resignFirstResponder()

return true

}



func textFieldDidEndEditing(_ textField: UITextField, reason: UITextFieldDidEndEditingReason) {



guard let record = object, let propertyName = propertyName else {return}



let oldValue = record[propertyName] as! String?

if textField.text != oldValue {

record[propertyName] = textField.text as CKRecordValue?

}

}



func isTextFieldDirty() -> Bool {



guard let record = object, let propertyName = propertyName else {return false}



let oldValue = record[propertyName] as! String?

return textField.text == oldValue ? false : true

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 Base class for local caches.
 
 */



import Foundation

import CloudKit



extension Notification.Name {

static let zoneCacheDidChange = Notification.Name("zoneCacheDidChange")

static let topicCacheDidChange = Notification.Name("topicCacheDidChange")

}



enum NotificationReason {

case zoneNotFound

case switchTopic

}



struct NotificationObjectKey {

static let reason = "reason"

static let recordIDsDeleted = "recordIDsDeleted"

static let recordsChanged = "recordsChanged"

static let newNote = "newNote"

}



class BaseLocalCache {



// A CloudKit task can be a single operation (CKDatabaseOperation) or multiple operations chained together.

// For a single-operation task, a completion handler can be enough because CKDatabaseOperation normally

// has a completeion handler to notify the client the task has been completed.

// For tasks that have chained operations, we need an operation queue to waitUntilAllOperationsAreFinished

// to know all the operations are done. This is useful for clients that need to update UI when everything is done.

//

lazy var operationQueue: OperationQueue = {

return OperationQueue()

}()



// This variable can be accessed from different queue

// > 0: TopicLocalCahce is changing and will be positing notifications. The cache is likely out of sync

//      with UI, so users should not edit the data based on what they see.

// ==0: No notification is pending. If there isn't any ongoing operation, the cache is synced.

//

private var pendingNotificationCount: Int = 0



// Post the notification after all the operations are done so that observers can update the UI

// This method can be tr-entried

//

func postNotificationWhenAllOperationsAreFinished(name: NSNotification.Name, object: NSDictionary? = nil) {



pendingNotificationCount += 1 // This method can be re-entried!



DispatchQueue.global().async {



self.operationQueue.waitUntilAllOperationsAreFinished()

DispatchQueue.main.async {

NotificationCenter.default.post(name: name, object: object)



self.pendingNotificationCount -= 1

assert(self.pendingNotificationCount >= 0)

}

}

}



// Return the subscription IDs used for current local cache.

//

func subscriptionIDs(databaseName: String, zone: CKRecordZone? = nil, recordType: String? = nil) -> [String] {



guard let zone = zone else { return [databaseName] }



let prefix = databaseName + "." + zone.zoneID.zoneName + "-" + zone.zoneID.ownerName

// Return identifier for the record type if it is specified.

//

if let recordType = recordType {

return [prefix + "." + recordType]

}

// If the record type is not specified, and the zone is the default one,

// return all valid IDs

//

if zone == CKRecordZone.default() {



return [prefix + "." + Schema.RecordType.topic,

prefix + "." + Schema.RecordType.note]

}

return [prefix]

}



// The cache is syncing if

// 1. there is an ongoing operation,

// 2. there is a notification being posted.

//

func isUpdating() -> Bool {

return operationQueue.operationCount > 0 || pendingNotificationCount > 0 ? true :  false

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 View controller class for picking a topic when editing a note.
 
 */



import UIKit

import CloudKit



extension Notification.Name {

static let topicDidPick = Notification.Name("topicDidPick")

}



class TopicPickerController: SpinnerViewController {



var topicPicked: Topic!



override func viewDidLoad() {

super.viewDidLoad()



NotificationCenter.default.addObserver(self, selector: #selector(type(of:self).topicCacheDidChange(_:)),

name: NSNotification.Name.topicCacheDidChange, object: nil)

navigationController?.isToolbarHidden = false

}



deinit {

NotificationCenter.default.removeObserver(self)

}



func topicCacheDidChange(_ notification: Notification) {

UIView.transition(with: tableView, duration: 0.4, options: .transitionCrossDissolve,

animations: {self.tableView.reloadData()})

}



override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

return TopicLocalCache.share.topics.count + 1

}



override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {



let cell = tableView.dequeueReusableCell(withIdentifier: TableCellReusableID.basic,

for: indexPath)

let topic: Topic

if indexPath.row == TopicLocalCache.share.topics.count {

topic = TopicLocalCache.share.orphanNoteTopic

}

else {

topic = TopicLocalCache.share.topics[indexPath.row]

}



cell.textLabel?.text = topic.record[Schema.Topic.name] as? String

cell.accessoryType = (topicPicked.record == topic.record) ? .checkmark : .none

return cell

}



override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {



if indexPath.row == TopicLocalCache.share.topics.count {

topicPicked = TopicLocalCache.share.orphanNoteTopic

}

else {

topicPicked = TopicLocalCache.share.topics[indexPath.row]

}

tableView.reloadData()

NotificationCenter.default.post(name: .topicDidPick, object: topicPicked)

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 App delegate class.
 
 */



import UIKit

import CloudKit

import UserNotifications



@UIApplicationMain

class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {



var window: UIWindow?



// Use CKContainer(identifier: <your custom container ID>) if not the default container.

// Note that:

// 1. iCloud container ID starts with "iCloud."

// 2. This will error out if iCloud / CloudKit entitlement is not well set up.

//

let container = CKContainer.default()



func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {



let storyboard = UIStoryboard(name: StoryboardID.main, bundle: nil)

let mainNC = storyboard.instantiateViewController(withIdentifier: StoryboardID.mainNC) as! UINavigationController

let zoneNC = storyboard.instantiateViewController(withIdentifier: StoryboardID.zoneNC) as! UINavigationController



window?.rootViewController = MenuViewController(mainViewController: mainNC, menuViewController: zoneNC)

window?.makeKeyAndVisible()



// Checking account availability. Create local cache objects if the accountStatus is available.

//

checkAccountStatus(for: container) {

ZoneLocalCache.share.initialize(container: self.container)

TopicLocalCache.share.initialize(container: self.container, database: self.container.privateCloudDatabase, zone: CKRecordZone.default())

}



// Register for remote notification.

// The local caches rely on subscription notifications, so notifications have to be granted in this sample.

//

let notificationCenter = UNUserNotificationCenter.current()

notificationCenter.requestAuthorization(options:[.badge, .alert, .sound]) { (granted, error) in

assert(granted == true)

}

application.registerForRemoteNotifications()



return true

}



// Note that to be able to accept a share, we need to have CKSharingSupported key in the info.plist and

// set its value to true. This is mentioned in the WWDC 2016 session 226 “What’s New with CloudKit”.

//

func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShareMetadata) {



let acceptSharesOp = CKAcceptSharesOperation(shareMetadatas: [cloudKitShareMetadata])

acceptSharesOp.acceptSharesCompletionBlock = { error in

guard CloudKitError.share.handle(error: error, operation: .acceptShare, alert: true) == nil else {return}

}

TopicLocalCache.share.container.add(acceptSharesOp)

}



func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any],

fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {



// When the app is transiting from background to foreground, appWillEnterForeground should have already

// refreshed the local cache, that's why we simply return here when application.applicationState == .inactive.

//

// Only notifications with a subscriptionID are interested in this sample.

//

guard let userInfo = userInfo as? [String: NSObject], application.applicationState != .inactive else {return}



let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)



guard let subscriptionID = notification.subscriptionID else {return}



// .database: CKDatabaseSubscription, used for synchronizing the ZoneLocalCahce.

// Note that CKDatabaseSubscription doesn't support the default zones.

//

if notification.notificationType == .database {

for database in ZoneLocalCache.share.databases where database.name == subscriptionID {



let validSubscriptionIDs = ZoneLocalCache.share.subscriptionIDs(databaseName: database.name)

if validSubscriptionIDs.index(where: {$0 == subscriptionID}) != nil {

ZoneLocalCache.share.fetchChanges(from: database)

}

}

return

}



// .readNotification: should have been handled. Ignore it.

//

if notification.notificationType == .readNotification {

return

}



// Now .query or .recordZone.

//

let databaseName = TopicLocalCache.share.container.displayName(of: TopicLocalCache.share.database)

let validSubscriptionIDs = TopicLocalCache.share.subscriptionIDs(databaseName: databaseName,

zone: TopicLocalCache.share.zone)



// .recordZone: CKRecordZoneSubscription, used for synchronizing the TopicLocalCahce.

// Note that CKRecordZoneSubscription doesn't support the default zone either.

//

if notification.notificationType == .recordZone {

guard let zoneNotification = notification as? CKRecordZoneNotification else {return}



// Silent out if the record zone subscription doesn't match the current TopicLocalCache.

//

guard validSubscriptionIDs.index(where: {$0 == subscriptionID}) != nil,

zoneNotification.recordZoneID == TopicLocalCache.share.zone.zoneID,

zoneNotification.databaseScope == TopicLocalCache.share.database.databaseScope else {return}



TopicLocalCache.share.fetchChanges()

}

// .query: for sync default zones, including the privateDB's default zone and publicDB.

// Note that CKQuerySubscription doesn't support sharedDB.

//

else if notification.notificationType == .query {

guard let queryNotification = notification as? CKQueryNotification else {return}



// Silent out if the record zone subscription doesn't match the current TopicLocalCache.

//

guard validSubscriptionIDs.index(where: {$0 == subscriptionID}) != nil,

queryNotification.recordID?.zoneID == TopicLocalCache.share.zone.zoneID,

queryNotification.databaseScope == TopicLocalCache.share.database.databaseScope else {return}



TopicLocalCache.share.update(withNotification: queryNotification)

}

}



// Report the error when failed to register the notifications.

//

func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {

print("!!! didFailToRegisterForRemoteNotificationsWithError: \(error)")

}



// When the application entering foreground again, update local cache.

//

func applicationWillEnterForeground(_ application: UIApplication) {



checkAccountStatus(for: container) {



if ZoneLocalCache.share.container == nil {

// Animate the spinner and build up the local cache.

//

DispatchQueue.main.async {

if let menuViewController = self.window?.rootViewController as? MenuViewController {



if let zoneNC = menuViewController.menuViewController as? UINavigationController,

let zoneViewController = zoneNC.viewControllers[0] as? ZoneViewController {

zoneViewController.spinner.startAnimating()

}

if let mainNC = menuViewController.mainViewController as? UINavigationController,

let mainViewController = mainNC.viewControllers[0] as? MainViewController {

mainViewController.spinner.startAnimating()

}

}

}

ZoneLocalCache.share.initialize(container: self.container)

TopicLocalCache.share.initialize(container: self.container,

database: self.container.privateCloudDatabase,

zone: CKRecordZone.default())

}

else {

// Update the zone local cache when the app comes back from background.

// ZoneLocalCache will trigger the fetchChanges of TopicLocalCache when it finds the current

// database/zone was changed.

//

for database in ZoneLocalCache.share.databases where database.cloudKitDB.databaseScope != .public {

ZoneLocalCache.share.fetchChanges(from: database)

}



// Default zones doesn't support fetchChanges, so do it seperately if it is current.

//

if TopicLocalCache.share.zone == CKRecordZone.default() {

TopicLocalCache.share.switchZone(newDatabase: TopicLocalCache.share.database,

newZone: TopicLocalCache.share.zone)

}

}

}

}



func applicationWillTerminate(_ application: UIApplication) {

NotificationCenter.default.removeObserver(self)

}



// Checking account availability. We do account check when the app comes back to foreground.

// We don't rely on ubiquityIdentityToken because it is not supported on tvOS and watchOS, while

// CloudKit is supported in those platforms.

//

// Silently return if everything goes well, or do a second check a while after the first failure.

//

private func checkAccountStatus(for container: CKContainer, completionHandler: (() -> Void)? = nil) {



container.accountStatus() { (status, error) in



if CloudKitError.share.handle(error: error, operation: .accountStatus, alert: true) == nil &&

status == CKAccountStatus.available {



if let completionHandler = completionHandler {completionHandler()}

return

}



DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { // Initiate the second check.



container.accountStatus() { (status, error) in



if CloudKitError.share.handle(error: error, operation: .accountStatus, alert: true) == nil &&

status == CKAccountStatus.available {



if let completionHandler = completionHandler {completionHandler()}

return

}



DispatchQueue.main.async {

let alert = UIAlertController(title: "iCloud account is unavailable.",

message: "Be sure to sign in iCloud and turn on iCloud Drive before using this sample.",

preferredStyle: .alert)

alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))

self.window?.rootViewController?.present(alert, animated: true)



// If the local cache is built up, clear it and reload the UI. This happens when userse turn off

// iCloud while this app is in background.

//

guard ZoneLocalCache.share.container != nil else {return}



// Clear the cache container and reload the whole UI stack.

//

ZoneLocalCache.share.container =  nil

TopicLocalCache.share.container = nil



let storyboard = UIStoryboard(name: StoryboardID.main, bundle: nil)

let mainNC = storyboard.instantiateViewController(withIdentifier: StoryboardID.mainNC) as! UINavigationController

let zoneNC = storyboard.instantiateViewController(withIdentifier: StoryboardID.zoneNC) as! UINavigationController

self.window?.rootViewController = MenuViewController(mainViewController: mainNC, menuViewController: zoneNC)

}

}

}

}

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 View controller class for managing topics and notes.
 
 */



import UIKit

import CloudKit



class MainViewController: ShareViewController {



override func viewDidLoad() {

super.viewDidLoad()



navigationItem.rightBarButtonItem = editButtonItem

navigationController?.isToolbarHidden = false

NotificationCenter.default.addObserver(self,

selector: #selector(type(of:self).topicCacheDidChange(_:)),

name: NSNotification.Name.topicCacheDidChange,

object: nil)

// Start spinner animation.

// TopicCacheDidChange should come soon, which will stop the animation

// if the local cache container is not ready, notification won't come though.

//

if TopicLocalCache.share.container != nil {

spinner.startAnimating()

}

}



override func viewWillAppear(_ animated: Bool) {



super.viewWillAppear(animated)

guard TopicLocalCache.share.container != nil else {return}



let databaseName = TopicLocalCache.share.container.displayName(of: TopicLocalCache.share.database)

title = databaseName + "." + TopicLocalCache.share.zone.zoneID.zoneName

}



deinit {

NotificationCenter.default.removeObserver(self)

}



override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {

if TopicLocalCache.share.isUpdating() {

alertCacheUpdating()

return false

}

return true

}



override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

guard let identifier = segue.identifier else {return}



if identifier == SegueID.mainShowDetail {



guard let indexPathSelected = tableView.indexPathForSelectedRow,

let noteViewController = segue.destination as? NoteViewController else {return}



noteViewController.topicOriginal = TopicLocalCache.share.visibleTopic(at: indexPathSelected.section)

noteViewController.note = noteViewController.topicOriginal.notes[indexPathSelected.row]

}

else if identifier == SegueID.mainAddNew {



guard let noteNC = segue.destination as? UINavigationController,

let noteViewController = noteNC.topViewController as? NoteViewController,

let topic = sender as? Topic else {return}



noteViewController.topicOriginal = topic



let _ = noteViewController.view // Load view fist to make sure the tableView is valid.

noteViewController.setEditing(true, animated: false)

}

}



override func setEditing(_ editing: Bool, animated: Bool) {

super.setEditing(editing, animated: animated)



tableView.bringSubview(toFront: spinner)

UIView.transition(with: tableView, duration: 0.4, options: .transitionCrossDissolve,

animations: {self.tableView.reloadData()})

}



@IBAction func toggleZone(_ sender: AnyObject) {

let menuViewController = view.window?.rootViewController as! MenuViewController

menuViewController.toggleMenu()

}

}



// Actions and handlers.

//

extension MainViewController {



// Notification is posted from main thread by cache class.

//

func topicCacheDidChange(_ notification: Notification) {

spinner.stopAnimating()



// .zoneNotfound: the current zone may be deleted by other peers,

// alert the user and switch to the default zone.

//

if let object = notification.object as? NSDictionary,

let reason = object[NotificationObjectKey.reason] as? NotificationReason, reason == .zoneNotFound {



var willShowAlert = true



// If MainViewController isn't at the top, NoteViewController should show the alert

// If the menu is on screen, sliently update the UI, rather than pop up an intruding alert.

//

if let visibleViewController = navigationController?.visibleViewController,

visibleViewController !== self {

willShowAlert = false

}

else if let menuViewController = view.window?.rootViewController as? MenuViewController,

menuViewController.isMenuHidden() == false {

willShowAlert = false

}



if willShowAlert == false {



spinner.startAnimating()

DispatchQueue.global().async {

TopicLocalCache.share.switchZone(newDatabase: TopicLocalCache.share.container.privateCloudDatabase,

newZone: CKRecordZone.default())

}

}

else {

// Alert users and switch to the default zone.

//

alertZoneDeleted()

}

return

}



tableView.reloadData()

let databaseName = TopicLocalCache.share.container.displayName(of: TopicLocalCache.share.database)

title = databaseName + "." + TopicLocalCache.share.zone.zoneID.zoneName

}



// Delete all records in current zone. Leaving this here for debug purpose.

//

func deleteAll(_ sender: AnyObject) {

guard !TopicLocalCache.share.isUpdating() else {alertCacheUpdating(); return}

spinner.startAnimating()

TopicLocalCache.share.deleteAll()

}



// Section title view button actions.

//

@IBAction func editTopic(_ sender: AnyObject) {

guard let sectionTitleView = (sender as? UIView)?.superview as? TopicSectionTitleView,

sectionTitleView.editingStyle != .none else {return}



guard !TopicLocalCache.share.isUpdating() else {alertCacheUpdating(); return}



let alert: UIAlertController

if sectionTitleView.editingStyle == .inserting {



alert = UIAlertController(title: "New Topic.", message: "Creating a topic.", preferredStyle: .alert)

alert.addTextField() { textField -> Void in textField.placeholder = "Name. Use 'Unnamed' if no input." }



alert.addAction(UIAlertAction(title: "New Topic", style: .default) {_ in



guard let name = alert.textFields![0].text else {return}

let finalName = name.isEmpty ? "Unnamed" : name



self.spinner.startAnimating()

TopicLocalCache.share.addTopic(with: finalName)

})

}

else { // Now sectionTitleView.editingStyle == .deleting.



// Adding a topic won't have any race condition.

// Theoritically there is a race condition on deleting: the topic may not be the same as what

// the user picks from the UI b/c the cache can be changed in the interval between

// the moment of picking and the moment of getting. However, with the above guard, it is safe to

// say that cahce changing (meaning notification -> cloudkit operations -> cache changing) can't happen in

// this short interval.

//

let topic = TopicLocalCache.share.topics[sectionTitleView.section] // Do this at the very beginning



alert = UIAlertController(title: "Deleting Topic.",

message: "Would you like to delete the topic and all its notes?",

preferredStyle: .alert)



alert.addAction(UIAlertAction(title: "Delete", style: .default) {_ in

self.spinner.startAnimating()

TopicLocalCache.share.deleteTopic(topic)

})

}

alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.default, handler: nil))

present(alert, animated: true, completion: nil)

}



@IBAction func shareTopic(_ sender: AnyObject) {

guard let sectionTitleView = (sender as? UIView)?.superview as? TopicSectionTitleView else {return}



guard !TopicLocalCache.share.isUpdating() else {alertCacheUpdating(); return}



let topic = TopicLocalCache.share.topics[sectionTitleView.section]



// Make sure there are no shared descendances under this topic if the topic is not yet shared.

// UICloudSharingController can be used to stop a share even if there are shared descendances.

//

if topic.record.share == nil {



for note in topic.notes where note.record.share != nil  {



var title = note.record[Schema.Note.title] as? String

title = title ?? "Untitled"

let alert = UIAlertController(title: "A note (\(title!)) under this topic has been shared.",

message: "Please stop sharing the note and try again.",

preferredStyle: .alert)

alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))

present(alert, animated: true)

return

}

}



// Everything looks good now, go ahead to share.

//

spinner.startAnimating()



// Topic name here may not unique so use a UUID string here.

//

// participantLookupInfos, if any, can be set up like this:

// let participantLookupInfos = [CKUserIdentityLookupInfo(emailAddress: "example@email.com"),

//                              CKUserIdentityLookupInfo(phoneNumber: "1234567890")]

DispatchQueue.main.async {

TopicLocalCache.share.container.prepareSharingController(

rootRecord: topic.record, uniqueName: UUID().uuidString, shareTitle: "A cool topic to share!",

participantLookupInfos: nil, database: TopicLocalCache.share.database) { controller in



self.rootRecord = topic.record

self.presentOrAlertOnMainQueue(sharingController: controller)

}

}

}

}



// Extension for UITableViewDataSource and UITableViewDelegate.

//

extension MainViewController {



override func numberOfSections(in tableView: UITableView) -> Int {



guard TopicLocalCache.share.container != nil else {return 0}



let visibleTopicCount = TopicLocalCache.share.visibleTopicCount()



if isEditing && TopicLocalCache.share.database.databaseScope != .shared {

return visibleTopicCount + 1

}

return visibleTopicCount

}



override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {



guard TopicLocalCache.share.container != nil else {return 0}



// When editing, there is an extra section for adding a new topic.

//

if section == TopicLocalCache.share.visibleTopicCount() {

return 0 // No notes for the section for adding a new topic.

}



// For sharedDB, adding a note into the orphan note topic is not allowed.

// And Users should not "add" a note if they can't write the topic.

//

let topic = TopicLocalCache.share.visibleTopic(at: section)

let topicNoteCount = topic.notes.count

let isSharedDB = (TopicLocalCache.share.database.databaseScope == .shared)



if topic.permission != .readWrite || (isSharedDB && TopicLocalCache.share.isOrphanSection(section)) {

return topicNoteCount

}



// Now either non-sharedDB, or the user has enough permission.

//

return isEditing ? topicNoteCount + 1 : topicNoteCount

}



override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {

return 44

}



override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {

let views = Bundle.main.loadNibNamed("TopicSectionTitleView",owner: self, options: nil)

let sectionTitleView = views?[0] as! TopicSectionTitleView



let isOrphanSection = TopicLocalCache.share.isOrphanSection(section)



// Set up editing style for the section title view.

// Default to add new status.

//

// Note that participants are not allowed to remove a topic because it is a root record.

//

var editingStyle: TopicSectionTitleView.EditingStyle = .inserting

var title = "Adding a topic"



if section < TopicLocalCache.share.visibleTopicCount() {

let topic = TopicLocalCache.share.visibleTopic(at: section)



if TopicLocalCache.share.database.databaseScope == .shared {

editingStyle = .none

}

else {

editingStyle = isEditing && !isOrphanSection && topic.permission == .readWrite ? .deleting : .none

}



title = (topic.record[Schema.Topic.name] as? String) ?? "Unnamed topic"

}



sectionTitleView.setEditingStyle(editingStyle, title: title)



// Set up share button.

// Hide share button for  the orphan topic.

// In the shareDB, a participant is valid to "share" a shared record as well,

// meaning they can show UICloudShareController for the following purpose:

// 1. See the list of invited people.

// 2. Send a copy of the share link to others (only if the share is public.

// 3. Leave the share.

//

if isOrphanSection {

sectionTitleView.shareButton.isHidden = true

}

else if TopicLocalCache.share.zone == CKRecordZone.default() {

sectionTitleView.shareButton.isEnabled = false

}



sectionTitleView.section = section // Save the section.

return sectionTitleView

}



override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

let cell = tableView.dequeueReusableCell(withIdentifier: TableCellReusableID.subTitle,

for: indexPath)

let topic = TopicLocalCache.share.visibleTopic(at:indexPath.section)



if indexPath.row == topic.notes.count {

cell.textLabel!.text = "Add a note"

}

else {

cell.textLabel!.text = topic.notes[indexPath.row].record[Schema.Note.title] as? String

}

cell.detailTextLabel?.text = nil

return cell

}



override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {

return true

}



override func tableView(_ tableView: UITableView,

editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {



let topic = TopicLocalCache.share.visibleTopic(at:indexPath.section)



// In public and private database, permission is default to .readWrite for the record creator.

// ShareDB is different:

// 1. A participant can always remove the participation by presenting a UICloudSharingController

// 2. A participant can change the record content if they have .readWrite permission.

// 3. A participant can add a record into a parent if they have .readWrite permission.

// 4. A participant can remove a record added by themselves from a parent.

// 5. A participant can not remove a root record if they are not the creator.

// 6. Users can not "add" a note if they can't write the topic. (Implemented in MainViewController.numberOfRowsInSection)

//

if topic.notes.count == indexPath.row {

return .insert

}



let note = topic.notes[indexPath.row]

if TopicLocalCache.share.database.databaseScope == .shared {



if let creatorID = note.record.creatorUserRecordID, creatorID.recordName == CKCurrentUserDefaultName {

return .delete

}

else {

return .none

}

}



return note.permission == .readWrite ? .delete : .none

}



override func tableView(_ tableView: UITableView,

shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {

return false

}



override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle,

forRowAt indexPath: IndexPath) {

guard !TopicLocalCache.share.isUpdating() else {alertCacheUpdating(); return}



// Theoretically there is a race condition here: the topic and note may not be the same as what

// the user picks from the UI. The reason is that the cache can be changed in the interval between

// the moment of picking and the moment of getting the item. However, with the above guard, it is safe to

// say that cahce changing (meaning notification -> cloudkit operations -> cache changing) can't happen in

// this short interval.

//

let topic = TopicLocalCache.share.visibleTopic(at: indexPath.section)



if editingStyle == .delete {

let note = topic.notes[indexPath.row]

spinner.startAnimating()

TopicLocalCache.share.deleteNote(note, topic: topic)

}

else {

performSegue(withIdentifier: SegueID.mainAddNew, sender: topic)

}

}

}

/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 Extensions of some CloudKit classes, implementing some reusable and convenient code.
 
 */



import UIKit

import CloudKit



extension CKDatabase {



// Add operation to the specified operation queue, or the database internal queue if

// there is no operation queue specified.

//

fileprivate func add(_ operation: CKDatabaseOperation, to queue: OperationQueue?) {



if let operationQueue = queue {

operation.database = self

operationQueue.addOperation(operation)

}

else {

add(operation)

}

}



fileprivate func configureQueryOperation(for operation: CKQueryOperation, results: NSMutableArray,

operationQueue: OperationQueue? = nil,

completionHandler: @escaping ((_ results: [CKRecord], _ moreComing: Bool, _ error: NSError?)->Void)) {



// recordFetchedBlock is called every time one record is fetched,

// so simply append the new record to the result set.

//

operation.recordFetchedBlock = { (record: CKRecord) in results.add(record) }



// Query completion block, continue to fetch if the cursor is not nil

//

operation.queryCompletionBlock = { (cursor, error) in



let moreComing = (cursor == nil) ? false : true

completionHandler(results as [AnyObject] as! [CKRecord], moreComing, error as NSError?)

if let cursor = cursor {

self.continueFetch(with: cursor, results: results, completionHandler: completionHandler)

}

}

}



fileprivate func continueFetch(with queryCursor: CKQueryCursor, results: NSMutableArray, operationQueue: OperationQueue? = nil,

completionHandler: @escaping ((_ results: [CKRecord], _ moreComing: Bool, _ error: NSError?)->Void)) {



let operation = CKQueryOperation(cursor: queryCursor)

configureQueryOperation(for: operation, results: results, completionHandler: completionHandler)

add(operation, to: operationQueue)

}



func fetchRecords(with recordType: String, desiredKeys: [String]? = nil, predicate: NSPredicate? = nil,

sortDescriptors: [NSSortDescriptor]? = nil, zoneID: CKRecordZoneID? = nil,

operationQueue: OperationQueue? = nil,

completionHandler: @escaping ((_ results: [CKRecord], _ moreComing: Bool, _ error: NSError?)->Void)) {



let query = CKQuery(recordType: recordType, predicate: predicate ?? NSPredicate(value: true))

query.sortDescriptors = sortDescriptors



let operation = CKQueryOperation(query: query)

operation.desiredKeys = desiredKeys

operation.zoneID = zoneID



// Using NSMutableArray, rather than [CKRecord] + inout parameter because

// 1. results will be captured in the recordFetchedBlock closure and pass out the data gathered there.

// 2. ther is no good way to use inout parameter in @escaping closure.

//

let results = NSMutableArray()

configureQueryOperation(for: operation, results: results, operationQueue: operationQueue, completionHandler: completionHandler)

add(operation, to: operationQueue)

}



// Use subscriptionID to create a subscriotion. Expect to hit an error of the subscritopn with the same ID

// already exists.

// Note that CKQuerySubscription is not supported in a sharedDB.

//

func addQuerySubscription(recordType: String, predicate: NSPredicate? = nil, subscriptionID: String,

options: CKQuerySubscriptionOptions, zoneID: CKRecordZoneID? = nil,

operationQueue: OperationQueue? = nil,

completionHandler:@escaping (NSError?) -> Void) {



let predicate = predicate ?? NSPredicate(value: true)



let subscription = CKQuerySubscription(recordType: recordType, predicate: predicate,

subscriptionID: subscriptionID, options: options)

subscription.zoneID = zoneID



let notificationInfo = CKNotificationInfo()

notificationInfo.shouldBadge = true

notificationInfo.alertBody = "A \(recordType) record was changed."



subscription.notificationInfo = notificationInfo



let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)



operation.modifySubscriptionsCompletionBlock = { _, _, error in

completionHandler(error as NSError?)

}



add(operation, to: operationQueue)

}



func addDatabaseSubscription(subscriptionID: String, operationQueue: OperationQueue? = nil,

completionHandler: @escaping (NSError?) -> Void) {



let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)



let notificationInfo = CKNotificationInfo()

notificationInfo.shouldBadge = true

notificationInfo.alertBody = "Database (\(subscriptionID)) was changed!"



subscription.notificationInfo = notificationInfo



let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)



operation.modifySubscriptionsCompletionBlock = { _, _, error in

completionHandler(error as NSError?)

}



add(operation, to: operationQueue)

}



func addRecordZoneSubscription(zoneID: CKRecordZoneID, subscriptionID: String? = nil,

operationQueue: OperationQueue? = nil,

completionHandler:@escaping (NSError?) -> Void) {



let subscription: CKRecordZoneSubscription

if subscriptionID == nil {

subscription = CKRecordZoneSubscription(zoneID: zoneID)

}

else {

subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: subscriptionID!)

}



let notificationInfo = CKNotificationInfo()

notificationInfo.shouldBadge = true

notificationInfo.alertBody = "A record zone (\(zoneID)) was changed!"



subscription.notificationInfo = notificationInfo



let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)



operation.modifySubscriptionsCompletionBlock = { _, _, error in

completionHandler(error as NSError?)

}



add(operation, to: operationQueue)

}





func delete(withSubscriptionIDs: [String], operationQueue: OperationQueue? = nil,

completionHandler:@escaping (NSError?) -> Void) {



let operation = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: withSubscriptionIDs)

operation.modifySubscriptionsCompletionBlock = { _, _, error in

completionHandler(error as NSError?)

}

add(operation, to: operationQueue)

}



// Fetch subscriptions with subscriptionIDs.

//

func fetchSubscriptions(with subscriptionIDs: [String]? = nil, operationQueue: OperationQueue? = nil,

completionHandler: (([String : CKSubscription]?, Error?) -> Void)? = nil) {



let operation: CKFetchSubscriptionsOperation



if let subscriptionIDs = subscriptionIDs {

operation = CKFetchSubscriptionsOperation(subscriptionIDs: subscriptionIDs)

}

else {

operation = CKFetchSubscriptionsOperation.fetchAllSubscriptionsOperation()

}

operation.fetchSubscriptionCompletionBlock = completionHandler

add(operation, to: operationQueue)

}



// Create a record zone with zone name and owner name.

//

func createRecordZone(with zoneName: String, ownerName: String, operationQueue: OperationQueue? = nil,

completionHandler: (([CKRecordZone]?, [CKRecordZoneID]?, Error?) -> Void)?) {



let zoneID = CKRecordZoneID(zoneName: zoneName, ownerName: ownerName)

let zone = CKRecordZone(zoneID: zoneID)

let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)

operation.modifyRecordZonesCompletionBlock = completionHandler



add(operation, to: operationQueue)

}



// Delete a record zone.

//

func delete(_ zoneID: CKRecordZoneID, operationQueue: OperationQueue? = nil,

completionHandler: (([CKRecordZone]?, [CKRecordZoneID]?, Error?) -> Void)?) {



let operation = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: [zoneID])

operation.modifyRecordZonesCompletionBlock = completionHandler



add(operation, to: operationQueue)

}

}





extension CKContainer {



// Database display names.

//

private struct DatabaseName {

static let privateDB = "Private"

static let publicDB = "Public"

static let sharedDB = "Shared"

}



func displayName(of database: CKDatabase) -> String {



if database.databaseScope == .public {

return DatabaseName.publicDB

}

else if database.databaseScope == .private {

return DatabaseName.privateDB

}

else if database.databaseScope == .shared {

return DatabaseName.sharedDB

}

else {

return ""

}

}



// When userIdentityLookupInfos contains an email that doesn't exist, userIdentityDiscoveredBlock

// will be called with uninitialized identity, causing an exception.

//

func discoverUserIdentities(with userIdentityLookupInfos: [CKUserIdentityLookupInfo]) {



let operation = CKDiscoverUserIdentitiesOperation(userIdentityLookupInfos: userIdentityLookupInfos)



operation.userIdentityDiscoveredBlock = { (identity, lookupInfo) in



if (identity as CKUserIdentity?) != nil {

print("userIdentityDiscoveredBlock: identity = \(identity), lookupInfo = \(lookupInfo)")

}

}



operation.discoverUserIdentitiesCompletionBlock = { error in

print("discoverUserIdentitiesCompletionBlock called!")

}



add(operation)

}



// Fetch participants from container and add them if the share is private.

// If a participant with a matching userIdentity already exists in this share,

// that existing participant’s properties are updated; no new participant is added

// Note that private users cannot be added to a public share.

//

fileprivate func addParticipants(to share: CKShare,

lookupInfos: [CKUserIdentityLookupInfo],

operationQueue: OperationQueue) {



if lookupInfos.count > 0 && share.publicPermission == .none {



let fetchParticipantsOp = CKFetchShareParticipantsOperation(userIdentityLookupInfos: lookupInfos)

fetchParticipantsOp.shareParticipantFetchedBlock = { participant in

share.addParticipant(participant)

}

fetchParticipantsOp.fetchShareParticipantsCompletionBlock = { error in

guard CloudKitError.share.handle(error: error, operation: .fetchRecords) == nil else {return}

}

fetchParticipantsOp.container = self

operationQueue.addOperation(fetchParticipantsOp)

}

}



// Set up UICloudSharingController for a root record. This is synchronous but can be called

// from any queue.

//

func prepareSharingController(rootRecord: CKRecord, uniqueName: String, shareTitle: String,

participantLookupInfos: [CKUserIdentityLookupInfo]? = nil,

database: CKDatabase? = nil,

completionHandler:@escaping (UICloudSharingController?) -> Void) {



let cloudDB = database ?? privateCloudDatabase



let operationQueue = OperationQueue()

operationQueue.maxConcurrentOperationCount = 1



// Share setup: fetch the share if the root record has been shared, or create a new one.

//

var sharingController: UICloudSharingController? = nil

var share: CKShare! = nil



if let shareRef = rootRecord.share {

// Fetch CKShare record if the root record has alreaad shared.

//

let fetchRecordsOp = CKFetchRecordsOperation(recordIDs: [shareRef.recordID])

fetchRecordsOp.fetchRecordsCompletionBlock = {recordsByRecordID, error in



let ret = CloudKitError.share.handle(error: error, operation: .fetchRecords, affectedObjects: [shareRef.recordID])

guard  ret == nil, let result = recordsByRecordID?[shareRef.recordID] as? CKShare else {return}



share = result



if let lookupInfos = participantLookupInfos {

self.addParticipants(to: share, lookupInfos: lookupInfos, operationQueue: operationQueue)

}

}

fetchRecordsOp.database = cloudDB

operationQueue.addOperation(fetchRecordsOp)



// Wait until all operation are finished.

// If share is still nil when all operations done, then there are errors.

//

operationQueue.waitUntilAllOperationsAreFinished()



if let share = share {

sharingController = UICloudSharingController(share: share, container: self)

}

}

else {



sharingController = UICloudSharingController(){(controller, prepareCompletionHandler) in



let shareID = CKRecordID(recordName: uniqueName, zoneID: TopicLocalCache.share.zone.zoneID)

share = CKShare(rootRecord: rootRecord, share: shareID)

share[CKShareTitleKey] = shareTitle as CKRecordValue

share.publicPermission = .none // default value.



// addParticipants is asynchronous, but will be executed before modifyRecordsOp because

// the operationqueue is serial.

//

if let lookupInfos = participantLookupInfos{

self.addParticipants(to: share, lookupInfos: lookupInfos, operationQueue: operationQueue)

}



// Clear the parent property because root record is now sharing independently.

// Restore it when the sharing is stoped if necessary (cloudSharingControllerDidStopSharing).

//

rootRecord.parent = nil



let modifyRecordsOp = CKModifyRecordsOperation(recordsToSave: [share, rootRecord], recordIDsToDelete: nil)

modifyRecordsOp.modifyRecordsCompletionBlock = { records, recordIDs, error in



// Use the serverRecord when a partial failure caused by .serverRecordChanged occurs.

// Let UICloudSharingController handle the other error, until failedToSaveShareWithError is called.

//

if let result = CloudKitError.share.handle(error: error, operation: .modifyRecords,affectedObjects: [shareID]) {

if let ckError = result[CloudKitError.Result.ckError] as? CKError,

let serverVersion = ckError.serverRecord as? CKShare {

share = serverVersion

}

}

prepareCompletionHandler(share, self, error)

}

modifyRecordsOp.database = cloudDB

operationQueue.addOperation(modifyRecordsOp)

}

}

completionHandler(sharingController)

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 A database wrapper for local caches.
 
 */



import Foundation

import CloudKit





// CloudKit database schema name constants.

//

struct Schema {

struct RecordType {

static let topic = "Topic"

static let note = "Note"

}

struct Topic {

static let name = "name"

}

struct Note {

static let title = "title"

static let topic = "topic"

}

}



class Database {

var serverChangeToken: CKServerChangeToken? = nil

let name: String

let cloudKitDB: CKDatabase

var zones: [CKRecordZone]



init(cloudKitDB: CKDatabase, container: CKContainer) {



self.name = container.displayName(of: cloudKitDB)

self.cloudKitDB = cloudKitDB

zones = [CKRecordZone]()



// Put the default zone as initial data because:

// 1. Public database dosen't support custom zone.

// 2. CKDatabaseSubscription doesn't capture the changes in the privateDB's default zone.

//

if cloudKitDB === container.publicCloudDatabase ||

cloudKitDB === container.privateCloudDatabase {

zones = [CKRecordZone.default()]

}

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 Table section header view calss, used in MainViewController for topic editing .
 
 */



import UIKit





class TopicSectionTitleButton: UIButton {



let xoffset: CGFloat = -8.0, space: CGFloat = 20.0

let imageSideLength: CGFloat = 28.0



override func imageRect(forContentRect contentRect: CGRect) -> CGRect {



if let sectionTitleView = superview as? TopicSectionTitleView {

if sectionTitleView.editingStyle == .none {

return super.titleRect(forContentRect: contentRect)

}

}

let yoffset: CGFloat = (contentRect.height - imageSideLength) / 2.0

return CGRect(x: xoffset, y: yoffset, width: imageSideLength, height: imageSideLength)

}



override func titleRect(forContentRect contentRect: CGRect) -> CGRect {



if let sectionTitleView = superview as? TopicSectionTitleView {

if sectionTitleView.editingStyle == .none {

return super.titleRect(forContentRect: contentRect)

}

}

return CGRect(x: contentRect.origin.x + xoffset + imageSideLength + space,

y: contentRect.origin.y,

width: contentRect.size.width - xoffset, height: contentRect.size.height)

}

}



class TopicSectionTitleView: UIView {



enum EditingStyle {

case none, inserting, deleting

}



@IBOutlet weak var titleButton: TopicSectionTitleButton!

@IBOutlet weak var shareButton: UIButton!



private(set) var editingStyle: EditingStyle = .none

var section: Int = -1



override func awakeFromNib() {



super.awakeFromNib()

backgroundColor = UIColor(red: 247/255, green: 247/255, blue: 247/255, alpha: 1)

titleButton.setTitleColor(.black, for: .normal)

shareButton.alpha = 0.0

}



func setEditingStyle(_ newStyle: EditingStyle, title: String) {



editingStyle = newStyle



switch newStyle {

case .none:

titleButton.setTitle(title, for: .normal)

titleButton.setImage(nil, for: .normal)

shareButton.alpha = 1.0



case .inserting:

titleButton.setTitle(title, for: .normal)

titleButton.setImage(UIImage(named: AssetNames.add), for: .normal)



case .deleting:

titleButton.setTitle(title, for: .normal)

titleButton.setImage(UIImage(named: AssetNames.cross), for: .normal)

titleButton.tintColor = .red

}

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 Base class for the view controllers in this sample.
 
 */



import UIKit

import CloudKit



// Use the TableView style name as the reusable ID.

// For a custom cell, use the class name.

//

struct TableCellReusableID {

static let basic = "Basic"

static let subTitle = "Subtitle"

static let rightDetail = "Right Detail"

static let textField = "TableViewTextFieldCell"

}



// Storybard ID constants.

//

struct StoryboardID {

static let main = "Main"

static let mainNC = "MainNC"

static let zoneNC = "ZoneNC"

static let note = "Note"

static let noteNC = "NoteNC"

}



// Segue ID constants.

//

struct SegueID {

static let topicPicker = "TopicPickerController"

static let mainShowDetail = "ShowDetail"

static let mainAddNew = "AddNew"

}



struct AssetNames {

static let menu = "menu24"

static let add = "circleAdd36"

static let cross = "circleCross36"

}



class SpinnerViewController: UITableViewController {



lazy var spinner: UIActivityIndicatorView = {

return UIActivityIndicatorView(activityIndicatorStyle: .gray)

}()



override func viewDidLoad() {

super.viewDidLoad()

tableView.addSubview(spinner)

tableView.bringSubview(toFront: spinner)

spinner.hidesWhenStopped = true

spinner.color = .blue

}



override func viewWillAppear(_ animated: Bool) {

super.viewWillAppear(animated)

spinner.center = CGPoint(x: tableView.frame.size.width / 2, y: tableView.frame.size.height / 2 - 88)

}



func alertCacheUpdating() {

let alert = UIAlertController(title: "Local cache is updating.",

message: "Try again after the update is done.",

preferredStyle: .alert)

alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))

present(alert, animated: true)



// Automatically dismiss after 1.5 second.

//

DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1.5){

alert.dismiss(animated: true, completion: nil)

}

}

}



class ShareViewController: SpinnerViewController, UICloudSharingControllerDelegate {



// Clients should set this before presenting UICloudSharingCloudller (presentOrAlertOnMainQueue)

// so that delegate method can access info in the root record.

//

var rootRecord: CKRecord?



func presentOrAlertOnMainQueue(sharingController: UICloudSharingController?) {



if let sharingController = sharingController {

DispatchQueue.main.async {

sharingController.delegate = self

sharingController.availablePermissions = [.allowPublic, .allowPrivate, .allowReadOnly, .allowReadWrite]

self.present(sharingController, animated: true) {

self.spinner.stopAnimating()

}

}

}

else {

DispatchQueue.main.async {

let alert = UIAlertController(title: "Failed to share.",

message: "Can't set up a valid share object.",

preferredStyle: .alert)

alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))

self.present(alert, animated: true) {

self.spinner.stopAnimating()

}

}

}

}



func alertZoneDeleted(completionHandler: (()->Void)? = nil) {



let alert = UIAlertController(title: "The current zone was deleted.",

message: "Switching to the default zone of the private database.",

preferredStyle: .actionSheet)

alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default) {_ in



// Stopping the last share in a zone seems to trigger two notifications. So at the moment when

// the user taps OK, the cache may have been updated, so have a check here.

//

if TopicLocalCache.share.database.databaseScope != .private ||

TopicLocalCache.share.zone.zoneID != CKRecordZone.default().zoneID {



self.spinner.startAnimating()

DispatchQueue.global().async {

TopicLocalCache.share.switchZone(newDatabase: TopicLocalCache.share.container.privateCloudDatabase,

newZone: CKRecordZone.default())

}

}

if let completionHandler = completionHandler { completionHandler() }



// After the local cache is updated, another notification will come to update the UI.

})

present(alert, animated: true)

}



func itemTitle(for csc: UICloudSharingController) -> String? {

guard let record = rootRecord else {return nil}



if record.recordType == Schema.RecordType.topic {

return record[Schema.Topic.name] as? String

}

else {

return record[Schema.Note.title] as? String

}

}



// When a topic is shared successfully, this method is called, the CKShare should have been created,

// and the whole share hierarchy should have been updated in server side. So fetch the changes and

// update the local cache.

//

func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {

TopicLocalCache.share.fetchChanges()

}



// When a share is stopped and this method is called, the CKShare record should have been removed and

// the root record should have been updated in the server side. So fetch the changes and update

// the local cache.

//

func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {



// Stop sharing can happen on two scenarios, a ower stop a share or a participant removes self from a share.

// In the former case, no visual things will be changed in the owner side (privateDB);

// in the latter case, the share will disappear from the sharedDB; and if the share is the only item in the

// current zone, the zone should also be removed.

// Note fetching immediately here may not get all the changes because the server side needs a while to index.

//

if TopicLocalCache.share.database.databaseScope == .shared, let record = rootRecord {



TopicLocalCache.share.deleteCachedRecord(record)



if TopicLocalCache.share.topics.count == 0, TopicLocalCache.share.orphanNoteTopic.notes.count == 0,

TopicLocalCache.share.database.databaseScope == .shared {



if let index = ZoneLocalCache.share.databases.index(where: {$0.cloudKitDB.databaseScope == .shared}) {

ZoneLocalCache.share.deleteCachedZone(TopicLocalCache.share.zone,

database: ZoneLocalCache.share.databases[index])

}

}

}

TopicLocalCache.share.fetchChanges() // Zone might not exist, which will trigger zone switching.

}



// Failing to save a share, show an alert and refersh the cache to avoid inconsistent status.

//

func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {



// Use error message directly for better debugging the error.

//

let alert = UIAlertController(title: "Failed to save a share.",

message: "\(error) ", preferredStyle: .alert)



alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))

self.present(alert, animated: true) {

self.spinner.stopAnimating()

}



// Fetch the root record from server and upate the rootRecord sliently.

// .fetchChanges doesn't return anything here, so fetch with the recordID.

//

if let rootRecordID = rootRecord?.recordID {

TopicLocalCache.share.update(withRecordID: rootRecordID)

}

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 View controller class for viewing and editing notes.
 
 */



import UIKit

import CloudKit



class NoteViewController: ShareViewController {



@IBOutlet var shareButtonItem: UIBarButtonItem!



// An editing copy for rolling back if an editing session is cancelled.

// We sync this copy when:

// 1. An editing session is cancelled.

// 2. A new note or note record is set.

// When saving the note, the record should synced.

//

fileprivate var editingCopyOfNoteRecord: CKRecord!



var note: Note! = nil {

didSet {

editingCopyOfNoteRecord = note.record.copy() as! CKRecord

}

}



var topicPicked: Topic!

var topicOriginal: Topic! = nil {

didSet {

topicPicked = topicOriginal

}

}

fileprivate var isAddNew = false



override func viewDidLoad() {



super.viewDidLoad()



// note == nil: no note specified, so create a new record and run in addnew mode.

// Create a new note record if note is nil

// Set up parent so that if the whole hierarchy is shared if the topic is shared.

//

if note == nil {

let noteRecord = CKRecord(recordType: Schema.RecordType.note, zoneID: TopicLocalCache.share.zone.zoneID)

note = Note(noteRecord: noteRecord, database: TopicLocalCache.share.database)



if topicOriginal !== TopicLocalCache.share.orphanNoteTopic {

note.record[Schema.Note.topic] = CKReference(record: topicOriginal.record,

action: .deleteSelf)

if TopicLocalCache.share.database.databaseScope != .public {

note.record.parent = CKReference(record: topicOriginal.record, action: .none)

}

}

isAddNew = true

title = "Add a New Note"

}



// Setup UI.

//

navigationItem.rightBarButtonItem = editButtonItem

navigationItem.rightBarButtonItem?.isEnabled = (note.permission == .readWrite) ? true :  false



NotificationCenter.default.addObserver(self, selector: #selector(type(of:self).topicCacheDidChange(_:)),

name: NSNotification.Name.topicCacheDidChange, object: nil)



NotificationCenter.default.addObserver(self, selector: #selector(type(of:self).topicDidPick(_:)),

name: NSNotification.Name.topicDidPick, object: nil)



// In the shareDB, a participant is valid to "share" a shared record as well,

// meaning they can show UICloudShareController for the following purpose:

// 1. See the list of invited people.

// 2. Send a copy of the share link to others (only if the share is public.

// 3. Leave the share.

//

let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target:nil, action: nil)

toolbarItems = [flexible, shareButtonItem, flexible]



updateShareItemEnable()

navigationController?.isToolbarHidden = false

}



deinit {

NotificationCenter.default.removeObserver(self)

}



override func setEditing(_ editing: Bool, animated: Bool) {



guard !(editing  && TopicLocalCache.share.isUpdating()) else { alertCacheUpdating(); return }



// Entering editing session, update the UI and return.

//

if editing {

super.setEditing(editing, animated: animated) // Call super's implementation first.

updateUI(editing: editing)

return

}



// Make sure the title field isn't empty.

//

let textFieldCell = noteTitleCell()! // tableView cells should have been setup. Otherwise trigger a crash.



if let input = textFieldCell.textField.text, input.isEmpty {



let alert = UIAlertController(title: "The title field is empty.",

message: "Please input a title and try again.",

preferredStyle: .alert)

alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default))

present(alert, animated: true)

return

}



super.setEditing(editing, animated: animated) // Call super's implementation first.



// Initiate the isDirty flag. Make sure it is true when adding a new record.

// TableViewTextFieldCell will set the value.

//

// Note that upateUI will reload the tableview and lose the isDirty flag in the original cell.

// so we don't updateUI before retrieving the isDirty flag.

//

var isDirty = isAddNew ? true : false



let newValue = textFieldCell.object![textFieldCell.propertyName!] as! String?

let oldValue = note.record[textFieldCell.propertyName!] as! String?

if newValue != oldValue {

note.record[textFieldCell.propertyName!] = newValue as CKRecordValue?

isDirty = true

}



if topicPicked !== topicOriginal {

isDirty = true

}



// If the record is not dirty, do nothing.

// CloudKit calls are expensive so save the changes only if the record is dirty.

//

if isDirty == false {

updateUI(editing: editing)

return

}



updateUI(editing: editing)

spinner.startAnimating()



// Remove the note from its original topic and add it into the new topic if a different topic is picked.

// Note and topicOriginal update will be triggered by the notificaiton after CloudKit operation returns.

//

if topicPicked !== topicOriginal {

TopicLocalCache.share.switchNoteTopic(note: note, orginalTopic: topicOriginal, newTopic: topicPicked)

}

else {

TopicLocalCache.share.saveNote(note, topic: topicPicked)

}

}



override func prepare(for segue: UIStoryboardSegue, sender: Any?) {



guard let identifier = segue.identifier, identifier == SegueID.topicPicker,

let picker = segue.destination as? TopicPickerController else {return}

picker.topicPicked = topicPicked

}

}



// Actions and handlers.

// Present different editing UI for adding a new note or editing an existing note.

//

extension NoteViewController {



fileprivate func updateShareItemEnable() {



if TopicLocalCache.share.database.databaseScope == .shared {

shareButtonItem.isEnabled = (note.record.share != nil)

}

else {

let enable = (TopicLocalCache.share.zone != CKRecordZone.default())

shareButtonItem.isEnabled = enable

}

}



fileprivate func updateUI(editing: Bool, animated: Bool = false) {



spinner.stopAnimating() // No harm if the spinner is not animtaing.

tableView.setEditing(editing, animated: animated)



// For edit, set the leftBarButtonItem to cancel and return.

//

if editing {

let item = UIBarButtonItem(barButtonSystemItem: .cancel, target: self,

action: #selector(type(of: self).cancelEditing(_:)))

navigationItem.leftBarButtonItem = item

shareButtonItem.isEnabled = false

return

}



// Now the user is stopping the edit.

// For add new, dismiss the view controller and return back to main view.

// For editing, update the title and left bar button item.

//

if isAddNew {

dismiss(animated: true)

}

else {

navigationItem.leftBarButtonItem = nil

tableView.reloadSections(IndexSet(integer: 0), with: .automatic)

updateShareItemEnable()

}

}



// Cancel editing. Use super.setEditing() implementation to avoid saving the changes.

//

func cancelEditing(_ sender: AnyObject) {



super.setEditing(false, animated: false)

topicPicked = topicOriginal // Back to the original topic



// The editing session is cancelled, so roll back to the original note.

//

editingCopyOfNoteRecord = note.record.copy() as! CKRecord



updateUI(editing: false)

}



// Notification is posted from main thread by cache class.

//

func topicCacheDidChange(_ notification: Notification) {



// Here we don't want to updateUI which will change the edit status and call dismiss in some cases.

// Simply reload the table data.

//

guard let object = notification.object as? NSDictionary else {

spinner.stopAnimating() // No harm if the spinner is not animating.

tableView.reloadData();

return

}



if let reason = object[NotificationObjectKey.reason] as? NotificationReason, reason == .zoneNotFound {



// Alert users and switch to the default zone.

//

alertZoneDeleted() {

if self.isAddNew {

self.dismiss(animated: true)

}

else {

_ = self.navigationController?.popViewController(animated: true)

}

}

return

}



// Note topic is switched, silently update the note and topicOriginal to be ready to edit again immediately.

// No UI update needed in this case, so sliently return.

//

if let reason = object[NotificationObjectKey.reason] as? NotificationReason, reason == .switchTopic {



if let newNote = object[NotificationObjectKey.newNote] as? Note {

note = newNote

topicOriginal = topicPicked

}

}



// If the note was deleted, alert the user and go back to the main screen.

// MainViewController should get the same notificaiton, so should have updated.

//

if let recordIDsDeleted = object[NotificationObjectKey.recordIDsDeleted] as? [CKRecordID] {



var isDeleted = false

if let _ = recordIDsDeleted.index(where: {$0 == self.topicOriginal.record.recordID}) {

isDeleted = true

}

else if let _ = recordIDsDeleted.index(where: {$0 == note.record.recordID}) {

isDeleted = true

}



if isDeleted {

let alert = UIAlertController(title: "This note was deleted by the other peer.",

message: "Tap OK to go back to the main screen.",

preferredStyle: .actionSheet)

alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default) {_ in



self.spinner.startAnimating()

_ = self.navigationController?.popToRootViewController(animated: true)

})

present(alert, animated: true)

return

}

}



// If the note was changed, alert the user and refresh the UI.

//

if let recordsChanged = object[NotificationObjectKey.recordsChanged] as? [CKRecord] {



var isChanged = false

if let index = recordsChanged.index(where: {$0.recordID == topicOriginal.record.recordID}) {



if !topicOriginal.isVisuallyEqual(to: recordsChanged[index]) {

isChanged = true

}

topicOriginal.record = recordsChanged[index]

}

else if let index = recordsChanged.index(where: {$0.recordID == note.record.recordID}) {



// The change might be triggered by sharing. In that case the visual content is not changed

// so we don't need an alert. Yet there may have an edit session ongoing or some unsaved changed

// that is not push to the note object yet. In that case, we should alert before reloading.

//

if topicOriginal !== topicPicked { // A new topic was picked, but the change is not saved.

isChanged = true

}

if let textFieldCell = noteTitleCell(), textFieldCell.isTextFieldDirty() { // Editing

isChanged = true

}

if !note.isVisuallyEqual(to: recordsChanged[index]) {

isChanged = true

}



note.record = recordsChanged[index]

editingCopyOfNoteRecord = note.record.copy() as! CKRecord

}



if isChanged {

let alert = UIAlertController(title: "This note was changed by the other peer.",

message: "Tap OK to refresh the data.",

preferredStyle: .actionSheet)

alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default) {_ in

self.cancelEditing(self) //

})

present(alert, animated: true)

return

}

}

// Here we don't want to updateUI which will change the edit status and call dismiss in some cases.

// Simply reload the table data.

//

spinner.stopAnimating() // No harm if the spinner is not animating.

tableView.reloadData()

}



// Notification handler for TopicDidPick posted by TopicPickerController from main thread.

//

func topicDidPick(_ notification: Notification) {



guard let newTopic = notification.object as? Topic else {return}

topicPicked = newTopic

tableView.reloadData()

}



// Delete all records in current zone.

//

@IBAction func shareNote(_ sender: AnyObject) {

guard !TopicLocalCache.share.isUpdating() else {alertCacheUpdating(); return}



// A participant isn't allowed to change the parent, so limit this to privateDB.

//

if TopicLocalCache.share.database.databaseScope == .private,

note.record.parent != nil, topicPicked.record.share !=  nil {



let alert = UIAlertController(title: "This note is already in a share hierarchy",

message: "Would you like to remove it from its current share hierarchy?",

preferredStyle: .alert)



alert.addAction(UIAlertAction(title: "Remove", style: .default) {_ in

self.spinner.startAnimating()



self.note.record.parent = nil

TopicLocalCache.share.saveNote(self.note, topic: self.topicPicked)

})

alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.default, handler: nil))

present(alert, animated: true, completion: nil)

}

else {

spinner.startAnimating()



// Note name here may not unique so use a UUID string here.

//

DispatchQueue.main.async {

TopicLocalCache.share.container.prepareSharingController(

rootRecord: self.note.record, uniqueName: UUID().uuidString,

shareTitle: "A cool note to share!", database: TopicLocalCache.share.database) { controller in



self.note.record.parent = nil // To share independently

self.rootRecord = self.note.record

self.presentOrAlertOnMainQueue(sharingController: controller)

}

}

}

}

}



// Extension for UITableViewDataSource and UITableViewDelegate.

//

extension NoteViewController {



fileprivate func noteTitleCell() -> TableViewTextFieldCell? {

return tableView.cellForRow(at: IndexPath(row: 1, section: 0)) as? TableViewTextFieldCell

}



override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

return 2

}



override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {



let identifiers = [TableCellReusableID.rightDetail, TableCellReusableID.textField]



let cell = tableView.dequeueReusableCell(withIdentifier: identifiers[indexPath.row], for: indexPath)



if indexPath.row == 0 {



cell.textLabel?.text = "Topic"

cell.detailTextLabel?.text = topicPicked.record[Schema.Topic.name] as? String

}

else if indexPath.row == 1, let textFieldCell = cell as? TableViewTextFieldCell {



textFieldCell.titleLabel.text = "Title"

textFieldCell.textField.placeholder = "Required"

textFieldCell.object = editingCopyOfNoteRecord

textFieldCell.propertyName = Schema.Note.title

}

return cell

}



override func tableView(_ tableView: UITableView,

editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {

return .none

}



override func tableView(_ tableView: UITableView,

shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {

return false

}



override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {



guard isEditing == true, let cell = tableView.cellForRow(at: indexPath) else {

tableView.deselectRow(at: indexPath, animated: true)

return

}



if cell.reuseIdentifier == TableCellReusableID.rightDetail {

performSegue(withIdentifier: SegueID.topicPicker, sender: cell)

}

else if cell.reuseIdentifier == TableCellReusableID.textField {

(cell as! TableViewTextFieldCell).textField.becomeFirstResponder()

}

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 Zone local cache class, managing the zone local cache.
 
 */



import Foundation

import CloudKit



final class ZoneLocalCache: BaseLocalCache {



static let share = ZoneLocalCache()



// Clients should call initialize(_:) to provide a container.

// Otherwise trigger a crash.

//

var container: CKContainer!

private(set) var databases: [Database]!



private override init() {} // Prevent clients from creating another instance.



// Subscribe the database changes and do the first fetch from server to build up the cache

// Rely on the notificaiton update to sync the cache later on.

// A known issue: CKDatabaseSubscription doesn't work for default zone of the private db yet.

//

// Subscribe the changes on the zone

// The cache is built after the subscriptions are created to avoid losing the changes made

// during the inteval.

//

// For changes on publicDB and the default zone of privateDB: CKQuerySubscription

// For changes on a custom zone of privateDB: CKDatabaseSubscription

// For changes on sharedDB: CKDatabaseSubscription.

//

// We use CKDatabaseSubscription to sync the changes on sharedDB and custom zones of privateDB

// CKRecordZoneSubscription is thus not used here.

//

// Note that CKRecordZoneSubscription doesn't support the default zone and sharedDB,

// and CKQuerySubscription doesn't support shardDB.

//

func initialize(container: CKContainer) {



guard self.container == nil else {return}

self.container = container



databases = [

Database(cloudKitDB: container.publicCloudDatabase, container: container),

Database(cloudKitDB: container.privateCloudDatabase, container: container),

Database(cloudKitDB: container.sharedCloudDatabase, container: container)

]



for database in databases where database.cloudKitDB.databaseScope != .public {



database.cloudKitDB.addDatabaseSubscription(

subscriptionID: subscriptionIDs(databaseName: database.name)[0],

operationQueue: operationQueue) { error in

guard CloudKitError.share.handle(error: error, operation: .modifySubscriptions, alert: true) == nil else {return}

self.fetchChanges(from: database)

}

}



for database in [container.publicCloudDatabase, container.privateCloudDatabase] {



let databaseName = container.displayName(of: database)

for recordType in [Schema.RecordType.topic, Schema.RecordType.note] {



let validIDs = subscriptionIDs(databaseName: databaseName,

zone: CKRecordZone.default(), recordType: recordType)

database.addQuerySubscription(

recordType: recordType, subscriptionID: validIDs[0],

options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion],

operationQueue: operationQueue) { error in

guard CloudKitError.share.handle(error: error, operation: .modifySubscriptions, alert: true) == nil else {return}

}

}

}

}



// Update the cache by fetching the database changes.

//

func fetchChanges(from database: Database) {



let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: database.serverChangeToken)

var zoneIDsChanged = [CKRecordZoneID]()



operation.changeTokenUpdatedBlock = { serverChangeToken in

database.serverChangeToken = serverChangeToken

}



operation.recordZoneWithIDWasDeletedBlock = { zoneID in



if let index = database.zones.index(where: {$0.zoneID == zoneID}) {

database.zones.remove(at: index)

}



guard database.cloudKitDB === TopicLocalCache.share.database &&

zoneID == TopicLocalCache.share.zone.zoneID else {return}



// Post a notification if the current zone is removed.

// Note that TopicLocalCache has an independent operation queue.

//

let notificationUserInfo = NSMutableDictionary()

notificationUserInfo.setValue(NotificationReason.zoneNotFound,

forKey: NotificationObjectKey.reason)

TopicLocalCache.share.postNotificationWhenAllOperationsAreFinished(

name: .topicCacheDidChange, object: notificationUserInfo)

}



operation.recordZoneWithIDChangedBlock = { zoneID in



zoneIDsChanged.append(zoneID)



// Sync TopicLocalCache if the current zone is changed.

// Note that TopicLocalCache has an independent operation queue.

//

guard database.cloudKitDB === TopicLocalCache.share.database &&

zoneID == TopicLocalCache.share.zone.zoneID else {return}



TopicLocalCache.share.fetchChanges()

}



operation.fetchDatabaseChangesCompletionBlock = { serverChangeToken, moreComing, error in



if CloudKitError.share.handle(error: error, operation: .fetchChanges, alert: true) != nil {

if let ckError = error as? CKError, ckError.code == .changeTokenExpired {

database.serverChangeToken = nil

self.fetchChanges(from: database) // Fetch changes again with nil token.

}

return

}



database.serverChangeToken = serverChangeToken

guard moreComing == false else {return}



let newZoneIDs = zoneIDsChanged.filter() {zoneID in

let index = database.zones.index(where: { zone in zone.zoneID == zoneID})

return index == nil ? true : false

}



guard newZoneIDs.count > 0 else {return}



let fetchZonesOp = CKFetchRecordZonesOperation(recordZoneIDs: newZoneIDs)

fetchZonesOp.fetchRecordZonesCompletionBlock = { results, error in



guard CloudKitError.share.handle(error: error, operation: .fetchRecords) == nil,

let zoneDictionary = results else {return}



for (_, zone) in zoneDictionary { database.zones.append(zone) }

database.zones.sort(){ $0.zoneID.zoneName < $1.zoneID.zoneName }

}



fetchZonesOp.database = database.cloudKitDB

self.operationQueue.addOperation(fetchZonesOp)

}

operation.database = database.cloudKitDB

operationQueue.addOperation(operation)

postNotificationWhenAllOperationsAreFinished(name: .zoneCacheDidChange)

}

}



extension ZoneLocalCache {



// Add a zone.

// A single-operation task, use completion handler to notify the clients. Not used in this sample.

//

func addZone(with zoneName: String, ownerName: String, to database: Database,

completionHandler:@escaping ([CKRecordZone]?, [CKRecordZoneID]?, Error?) -> Void) {



database.cloudKitDB.createRecordZone(with: zoneName, ownerName: ownerName){ zones, zoneIDs, error in



if CloudKitError.share.handle(error: error, operation: .modifyZones, alert: true) == nil {

database.zones.append(zones![0])

database.zones.sort(by:{ $0.zoneID.zoneName < $1.zoneID.zoneName })

}

completionHandler(zones, zoneIDs, error)

}

}



func saveZone(with zoneName: String, ownerName: String, to database: Database) {



let zoneID = CKRecordZoneID(zoneName: zoneName, ownerName: ownerName)

let newZone = CKRecordZone(zoneID: zoneID)

let operation = CKModifyRecordZonesOperation(recordZonesToSave: [newZone], recordZoneIDsToDelete: nil)



operation.modifyRecordZonesCompletionBlock = { (zones, zoneIDs, error) in

guard CloudKitError.share.handle(error: error, operation: .modifyZones, alert: true) == nil,

let savedZone = zones?[0] else {return}



if database.zones.index(where: {$0 == savedZone}) == nil {

database.zones.append(savedZone)

}

database.zones.sort(by:{ $0.zoneID.zoneName < $1.zoneID.zoneName })



}

operation.database = database.cloudKitDB

operationQueue.addOperation(operation)

postNotificationWhenAllOperationsAreFinished(name: .zoneCacheDidChange)

}



// Delete a zone.

// A single-operation task, use completion handler to notify the clients. Not used in this sample.

//

func delete(_ zone: CKRecordZone, from database: Database,

completionHandler: @escaping ([CKRecordZone]?, [CKRecordZoneID]?, Error?) -> Void) {



database.cloudKitDB.delete(zone.zoneID) { zones, zoneIDs, error in



if CloudKitError.share.handle(error: error, operation: .modifyZones, alert: true) == nil {

if let index = database.zones.index(of: zone) {

database.zones.remove(at: index)

}

}

completionHandler(zones, zoneIDs, error)

}

}



func deleteZone(_ zone: CKRecordZone, from database: Database) {



let operation = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: [zone.zoneID])

operation.modifyRecordZonesCompletionBlock = { (_, _, error) in



guard CloudKitError.share.handle(error: error, operation: .modifyRecords, alert: true) == nil,

let index = database.zones.index(of: zone) else {return}

database.zones.remove(at: index)

}

operation.database = database.cloudKitDB

operationQueue.addOperation(operation)

postNotificationWhenAllOperationsAreFinished(name: .zoneCacheDidChange)

}



func deleteCachedZone(_ zone: CKRecordZone, database: Database) {



if let index = database.zones.index(of: zone) {

database.zones.remove(at: index)

postNotificationWhenAllOperationsAreFinished(name: .zoneCacheDidChange)

}

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 Topic and note local cache class, managing the local cache for topics and notes.
 
 */



import Foundation

import CloudKit



final class TopicLocalCache: BaseLocalCache {

static let share = TopicLocalCache()



var container: CKContainer!

var database: CKDatabase!

var zone = CKRecordZone.default()



var serverChangeToken: CKServerChangeToken? = nil



var topics = [Topic]()

var orphanNoteTopic: Topic!



private override init() {} // Prevent clients from creating another instance.



func initialize(container: CKContainer, database: CKDatabase, zone: CKRecordZone) {



guard self.container == nil else {

print("This call is ignored because local cache singleton has be initialized!")

return

}

self.container = container



// Create the temp topic for orphan notes.

//

let topicRecord = CKRecord(recordType: Schema.RecordType.topic, zoneID: zone.zoneID)

topicRecord[Schema.Topic.name] = "No-topic notes" as CKRecordValue?

orphanNoteTopic = Topic(topicRecord: topicRecord, database: database)



switchZone(newDatabase: database, newZone: zone)

}



fileprivate func sortTopics() {



topics.sort(){ topic0, topic1 in

guard let name0 = topic0.record[Schema.Topic.name] as? String,

let name1 = topic1.record[Schema.Topic.name] as? String else {return false}

return name0 < name1

}

}



// Remove the deleted reocrds from the cached. Topic records are handled first.

// If a topic record is removed, the notes of the topic will be removed as well.

// SharedDB is different though, records that are independantly shared should go to orphantopic.

//

private func update(withRecordIDsDeleted: [CKRecordID]) {



let isSharedDB = database.databaseScope == .shared ? true : false

var orphanTopicChanged = false



var noteIDsDeleted = [CKRecordID]()



for recordID in withRecordIDsDeleted {



if let index = topics.index(where: { $0.record.recordID == recordID }) {



if isSharedDB { // Moved independently shared notes to orphen topic. Only shre sharedDB.

for note in topics[index].notes {

if note.record.share != nil {

orphanNoteTopic.notes.append(note)

orphanTopicChanged = true

}

}

}

topics.remove(at: index)

}

else {

noteIDsDeleted.append(recordID)

}

}



noteIDLoop: for recordID in noteIDsDeleted {



if let index = orphanNoteTopic.notes.index(where: { $0.record.recordID == recordID }) {

orphanNoteTopic.notes.remove(at: index)

continue noteIDLoop

}



for topic in topics {

if let index = topic.notes.index(where: { $0.record.recordID == recordID }) {

topic.notes.remove(at: index)

continue noteIDLoop

}

}

// else: notes that doesn't belong to a topic, which should have been removed.

}



if isSharedDB && orphanTopicChanged { orphanNoteTopic.sortNotes() }

}



// Process the changed topics. The records not found in the existing cache are new.

// There are several things to consider:

// 1. For a new sharing topic:

// the root record and the share record will both in withRecordsChanged, so we can retrieve the

// permission from the share record.

//

// 2. For a sharing note:

// a. It is shared because its parent is shared, thus no share record is created and

// no share record in withRecordsChanged. The permission should be the same as the parent.

// b. It is shared independently, so a new share record is created, and is in withRecordsChanged.

//

// 3. For a permission change:

// Only the associated share record is changed, and in withRecordsChanged. So we have to go through

// the local cache to update the permission.

//

private func update(withRecordsChanged: [CKRecord]) {



// We can make a mutable copy of withRecordsChanged and remove the processed items in the loop

// That however isn't necessarily better given withRecordsChanged won't be a big array,so simply

// use the immutable one and go through every items every time.

//

// We only care CKShare and CKSharePermission when we are currently in sharedDB.

//

let isSharedDB = database.databaseScope == .shared ? true : false



// Gather the share records first, only for sharedDB.

//

var sharesChanged = [CKShare]()

if isSharedDB {

for record in withRecordsChanged where record is CKShare {

sharesChanged.append(record as! CKShare)

}

}



// True if there are changed topics so we need to sort the topics later.

// topics can be large, so make sure we don't sort it unnecessarily.

//

var isTopicNameChanged = false



// Gathering the newly added topic record for later use.

//

var newTopicRecords = [CKRecord]()



for record in withRecordsChanged where record.recordType == Schema.RecordType.topic {



var topicChanged: Topic



if let index = topics.index(where: { $0.record.recordID == record.recordID }) {



topicChanged = topics[index]



if let oldName = topicChanged.record[Schema.Topic.name] as? String,

let newName = record[Schema.Topic.name] as? String, oldName != newName {

isTopicNameChanged = true // Topic name is changed, so sort the topics later.

}



topicChanged.record = record

}

else {



isTopicNameChanged = true // At least one new topic, so sort the topic later.



topicChanged = Topic(topicRecord: record, database: database)

topics.append(topicChanged)



topicChanged.fetchNotes(from: database, operationQueue: operationQueue)

newTopicRecords.append(record)

}



// Set permission with the gathered share records if matched.

// Remove the processed share from sharesChanged. Only do this for sharedDB.

//

if isSharedDB, sharesChanged.count > 0, let index = topicChanged.setPermission(with: sharesChanged) {

sharesChanged.remove(at: index)

}

}



// Sort the topics by name if topics are changed.

//

if isTopicNameChanged { sortTopics() }





// Now process the newly changed notes.

// If the note belongs to a new created topic, it should be fetched in Topic.init

// If a note doesn't have a topic, it goes to orphanNoteTopic.

//

var unsortedTopicIndice = [Int](), isOrphanTopicSorted = false



for record in withRecordsChanged where record.recordType == Schema.RecordType.note {



var noteChanged: Note, isNoteNameChanged = false

var topic: Topic! = nil, topicIndex: Int? = nil



if let topicRef = record[Schema.Note.topic] as? CKReference {



guard newTopicRecords.index(where: {$0.recordID == topicRef.recordID}) == nil else {continue}



if let index = topics.index(where: {$0.record.recordID == topicRef.recordID}) {

topic = topics[index]

topicIndex = index

}

}



// If the note doesn't belong to one of newTopicRecords or existing records,

// put it into orphan topic

//

topic = topic ?? orphanNoteTopic



if let noteIndex = topic.notes.index(where: {$0.record.recordID == record.recordID}) {



noteChanged = topic.notes[noteIndex]



if let oldTitle = noteChanged.record[Schema.Note.title] as? String,

let newTitle = record[Schema.Note.title] as? String, oldTitle != newTitle {

isNoteNameChanged = true // Name is changed, so sort notes later.

}



noteChanged.record = record

}

else {



noteChanged = Note(noteRecord: record, database: database)

if isSharedDB { // Default to parent permission if it is a sharedDB record.

noteChanged.permission = topic.permission

}

topic.notes.append(noteChanged)



isNoteNameChanged = true // New note, so sort the notes later.

}



// Manage the sorted status if the note name is changed.

// topicIndex!: now the topic should be either a normal topic, or the orphan topic.

//

if isNoteNameChanged {

if topic === orphanNoteTopic {

isOrphanTopicSorted = true

}

else if unsortedTopicIndice.index(where: {$0 == topicIndex!}) == nil {

unsortedTopicIndice.append(topicIndex!)

}

}



// Note that if the note is shared independently, there should have a match share record.

// Otherwise, changedNote.permission is default to topic.permission.

//

if isSharedDB, sharesChanged.count > 0, let index = noteChanged.setPermission(with: sharesChanged) {

sharesChanged.remove(at: index)

}

}



// Sort the notes array of changed Topics or orphanNoteTopic.

//

for index in unsortedTopicIndice {

topics[index].sortNotes()

}

if isOrphanTopicSorted {

orphanNoteTopic.sortNotes()

}



guard isSharedDB, sharesChanged.count > 0 else {return}



// Now there are some share records that are changed but not processed. This happens when useres changed

// the share options, which only affect the share record, not the root record.

// In that case, we have to go through the whole TopicLocalCache to find the right item and upate its permission.

//

// sharesChanged should normally contain one item so we just loop all the item here.

//

let allTopics = topics + [orphanNoteTopic]



shareLoop: for share in sharesChanged {



for var topic in allTopics {



// orphanNoteTopic has a fake topic record, still ok.

//

if topic.setPermission(with: [share]) != nil {

continue shareLoop // Continue to process the next share changed.

}



// notes under the topic, including orphanNoteTopic.

//

for var note in topic.notes {

if note.setPermission(with: [share]) != nil {

continue shareLoop // Continue to process the next share changed.

}

}

}

}

}



// Refresh the cache for the default zones which don't support fetching changes,

// including the public database and the private database's default zone.

//

private func fetchCurrentZone() {



topics.removeAll() // Clear current cache.



let sortDescriptor = NSSortDescriptor(key: Schema.Topic.name, ascending: true)



database.fetchRecords( with: Schema.RecordType.topic, sortDescriptors: [sortDescriptor],

zoneID: zone.zoneID, operationQueue: operationQueue) {(results, moreComing, error) in



guard CloudKitError.share.handle(error: error, operation: .fetchRecords, alert: true) == nil else {return}



for record in results {

let topic = Topic(topicRecord: record, database: self.database)

self.topics.append(topic)

topic.fetchNotes(from: self.database, operationQueue: self.operationQueue)

}

}



DispatchQueue.global().async {

self.operationQueue.waitUntilAllOperationsAreFinished()



let references = self.topics.map(){CKReference(record: $0.record, action: .deleteSelf)}

let predicate = NSPredicate(format: "Not (%K IN %@)", Schema.Note.topic, references)

self.orphanNoteTopic.fetchNotes(from: self.database, predicate: predicate, operationQueue: self.operationQueue)



self.postNotificationWhenAllOperationsAreFinished(name: .topicCacheDidChange)

}

}



// Update the cache by fetching the database changes.

// Note that fetching changes is only supported in custom zones.

//

func fetchChanges() {



// Use NSMutableDictionary, rather than Swift dictionary

// because this may be changed in the completion handler.

//

let notificationObject = NSMutableDictionary()



let options = CKFetchRecordZoneChangesOptions()

options.previousServerChangeToken = serverChangeToken



let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zone.zoneID],

optionsByRecordZoneID: [zone.zoneID: options])



// Gather the changed records for processing in a batch.

//

var recordsChanged = [CKRecord]()

operation.recordChangedBlock = { record in

recordsChanged.append(record)

}



var recordIDsDeleted = [CKRecordID]()

operation.recordWithIDWasDeletedBlock = { (recordID, string) in

recordIDsDeleted.append(recordID)

}



operation.recordZoneChangeTokensUpdatedBlock = {(zoneID, serverChangeToken, clientChangeTokenData) in

assert(zoneID == self.zone.zoneID)

self.serverChangeToken = serverChangeToken

}



operation.recordZoneFetchCompletionBlock = {

(zoneID, serverChangeToken, clientChangeTokenData, moreComing, error) in



if CloudKitError.share.handle(error: error, operation: .fetchChanges) != nil,

let ckError = error as? CKError  {



// Fetch changes again with nil token if the token has expired.

// .zoneNotfound error is handled in fetchRecordZoneChangesCompletionBlock as a partial error.

//

if ckError.code == .changeTokenExpired {

self.serverChangeToken = nil

self.fetchChanges()

}

return

}

assert(zoneID == self.zone.zoneID && moreComing == false)

self.serverChangeToken = serverChangeToken

}



operation.fetchRecordZoneChangesCompletionBlock = { error in



// The zone has been deleted, notify the clients so that they can update UI.

//

if let result = CloudKitError.share.handle(error: error, operation: .fetchChanges,

affectedObjects: [self.zone.zoneID], alert: true) {



if let ckError = result[CloudKitError.Result.ckError] as? CKError, ckError.code == .zoneNotFound {



notificationObject.setValue(NotificationReason.zoneNotFound,

forKey: NotificationObjectKey.reason)

}

return

}

// Push recordIDsDeleted and recordsChanged into notification payload.

//

notificationObject.setValue(recordIDsDeleted, forKey: NotificationObjectKey.recordIDsDeleted)

notificationObject.setValue(recordsChanged, forKey: NotificationObjectKey.recordsChanged)



// Do the update.

//

self.update(withRecordIDsDeleted: recordIDsDeleted)

self.update(withRecordsChanged: recordsChanged)

}

operation.database = database

operationQueue.addOperation(operation)

postNotificationWhenAllOperationsAreFinished(name: .topicCacheDidChange, object: notificationObject)

}



// Convenient method to update the cache with one specified record ID.

//

func update(withRecordID recordID: CKRecordID) {



let fetchRecordsOp = CKFetchRecordsOperation(recordIDs: [recordID])

fetchRecordsOp.fetchRecordsCompletionBlock = {recordsByRecordID, error in



let ret = CloudKitError.share.handle(error: error, operation: .fetchRecords, affectedObjects: [recordID])

guard  ret == nil, let record = recordsByRecordID?[recordID]  else {return}



self.update(withRecordsChanged: [record])



}

fetchRecordsOp.database = database

operationQueue.addOperation(fetchRecordsOp)

postNotificationWhenAllOperationsAreFinished(name: .topicCacheDidChange)

}



// Update the cache with CKQueryNotification. For defaults zones that don't support fetching changes,

// including the privateDB's default zone and publicDB.

// Fetching changes is not supported in the default zone, so use CKQuerySubscription to get notified of changes.

// Since push notifications can be coalesced, CKFetchNotificationChangesOperation is used to get the coalesced

// notifications (if any) and keep the data synced.

// Otherwise, we have to fetch the whole zone,

// or move the data to custom zones which are only supported in the private database.

//

func update(withNotification notification: CKQueryNotification) {



// Use NSMutableDictionary, rather than Swift dictionary

// because this may be changed in the completion handler.

//

let notificationObject = NSMutableDictionary()



let operation = CKFetchNotificationChangesOperation(previousServerChangeToken: serverChangeToken)



var notifications: [CKNotification] = [notification]

operation.notificationChangedBlock = {

notification in notifications.append(notification)

}



operation.fetchNotificationChangesCompletionBlock = { (token, error) in

guard CloudKitError.share.handle(error: error, operation: .fetchChanges) == nil else {return}



self.serverChangeToken = token // Save the change token, which will be used in next time fetch.



var recordIDsDeleted = [CKRecordID](), recordIDsChanged = [CKRecordID]()



for aNotification in notifications where aNotification.notificationType != .readNotification {



guard let queryNotification = aNotification as? CKQueryNotification else {continue}



if queryNotification.queryNotificationReason == .recordDeleted {

recordIDsDeleted.append(queryNotification.recordID!)

}

else {

recordIDsChanged.append(queryNotification.recordID!)

}

}



// Update the cache with recordIDsDeleted.

//

if recordIDsDeleted.count > 0 {

notificationObject.setValue(recordIDsDeleted, forKey: NotificationObjectKey.recordIDsDeleted)

self.update(withRecordIDsDeleted: recordIDsDeleted)



recordIDsChanged = recordIDsChanged.filter({

recordIDsDeleted.index(of: $0) == nil ? true : false

})

}



// Fetch the changed record with record IDs and update the cache with the records.

// In the iCloud environment, .unknownItem errors may happen because the items are removed by other peers,

// so simply igore the error.

//

if recordIDsChanged.count > 0 {



let fetchRecordsOp = CKFetchRecordsOperation(recordIDs: recordIDsChanged)

var recordsChanged = [CKRecord]()

fetchRecordsOp.fetchRecordsCompletionBlock = { recordsByRecordID, error in



if let result = CloudKitError.share.handle(error: error, operation: .fetchRecords,

affectedObjects: recordIDsChanged) {



if let ckError = result[CloudKitError.Result.ckError] as? CKError,

ckError.code != .unknownItem {

return

}

}

if let records = recordsByRecordID?.values {

recordsChanged = Array(records)

}

notificationObject.setValue(recordsChanged, forKey: NotificationObjectKey.recordsChanged)

self.update(withRecordsChanged: recordsChanged)

}

fetchRecordsOp.database = self.database

self.operationQueue.addOperation(fetchRecordsOp)

}



// Mark the notifications read so that they won't appear in the future fetch.

//

let notificationIDs = notifications.flatMap{$0.notificationID} //flatMap: filter nil values.

let markReadOp = CKMarkNotificationsReadOperation(notificationIDsToMarkRead: notificationIDs)

markReadOp.markNotificationsReadCompletionBlock = { notificationIDs, error in

guard CloudKitError.share.handle(error: error, operation: .markRead) == nil else {return}

}

self.container.add(markReadOp) // No impact on UI so use the internal queue.



// Push recordIDsDeleted and recordsChanged into notification payload.

//

}



operation.container = container

operationQueue.addOperation(operation)

postNotificationWhenAllOperationsAreFinished(name: .topicCacheDidChange, object: notificationObject)

}



// Subscribe the changes of the specified zone and do the first-time fetch to build up the cache.

//

func switchZone(newDatabase: CKDatabase, newZone: CKRecordZone) {



// Update the zone info.

//

database = newDatabase

zone = newZone



// Clear all topics and notes, including the orphan notes of orphanNoteTopic.

//

topics.removeAll()

orphanNoteTopic.notes.removeAll()



if newZone == CKRecordZone.default() {

fetchCurrentZone() // Fetch all records at the very beginning.

}

else {

serverChangeToken = nil

fetchChanges() // Fetching changes with nil token to build up the cache.

}

}

}



// Convenient methods for the database editing from UI.

//

extension TopicLocalCache {



// true: the specified section points to the orphan-note section.

// false: not the the orphan-note section.

//

func isOrphanSection(_ section: Int) -> Bool {

return orphanNoteTopic.notes.count > 0 && section == topics.count ? true : false

}



// Visible topics means the topics visible to users.

// When there is something in the orphan section, the orphan section will be visible,

// so visible topics will include the orphan-note topic. Otherwise, they are simply the data

// in topics array.

//

func visibleTopicCount() -> Int {

let orphanSection = orphanNoteTopic.notes.count > 0 ? 1 : 0

return topics.count + orphanSection

}



func visibleTopic(at section: Int) -> Topic {

assert(section < visibleTopicCount())

return (section < topics.count) ? topics[section] : orphanNoteTopic

}



func addTopic(with name: String) {



let newRecord = CKRecord(recordType: Schema.RecordType.topic, zoneID: zone.zoneID)

newRecord[Schema.Topic.name] = name as CKRecordValue?



let operation = CKModifyRecordsOperation(recordsToSave: [newRecord], recordIDsToDelete: nil)



operation.modifyRecordsCompletionBlock = { (records, recordIDs, error) in

guard CloudKitError.share.handle(error: error, operation: .modifyRecords, alert: true) == nil,

let newRecord = records?[0] else {return}



let topic = Topic(topicRecord: newRecord, database: self.database) // New Topic so no need to fetch its notes

self.topics.append(topic)



// Sort the topics by name.

//

self.sortTopics()

}

operation.database = database

operationQueue.addOperation(operation)

postNotificationWhenAllOperationsAreFinished(name: .topicCacheDidChange)

}



// Use topic rather than index because the cache may be changing so we can't rely on index.

//

func deleteTopic(_ topic: Topic) {



let recordID = topic.record.recordID

let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])



operation.modifyRecordsCompletionBlock = { (_, _, error) in

guard CloudKitError.share.handle(error: error, operation: .modifyRecords, alert: true) == nil else {return}



if let index = self.topics.index(where: {$0.record.recordID == topic.record.recordID}) {

self.topics.remove(at: index)

}

}

operation.database = database

operationQueue.addOperation(operation)

postNotificationWhenAllOperationsAreFinished(name: .topicCacheDidChange)

}



func saveNote(_ noteToSave: Note, topic: Topic) {



let operation = CKModifyRecordsOperation(recordsToSave: [noteToSave.record], recordIDsToDelete: nil)

operation.modifyRecordsCompletionBlock = { (records, recordIDs, error) in



guard CloudKitError.share.handle(error: error, operation: .modifyRecords, alert: true) == nil,

let savedRecord = records?[0] else {return}



if topic.notes.index(where: {$0.record.recordID == savedRecord.recordID}) == nil {

topic.notes.append(Note(noteRecord:savedRecord, database: self.database))

}



topic.sortNotes()

}

operation.database = database

operationQueue.addOperation(operation)

postNotificationWhenAllOperationsAreFinished(name: .topicCacheDidChange)

}



// Use note / topic rather than indexPath because the cache may be changing so we can't rely on indexPath.

//

func deleteNote(_ note: Note, topic: Topic) {



let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [note.record.recordID])



operation.modifyRecordsCompletionBlock = { (_, _, error) in

guard CloudKitError.share.handle(error: error, operation: .modifyRecords, alert: true) == nil else {return}



if let index = topic.notes.index(where: {$0.record.recordID == note.record.recordID}) {

topic.notes.remove(at: index)

}

}

operation.database = database

operationQueue.addOperation(operation)

postNotificationWhenAllOperationsAreFinished(name: .topicCacheDidChange)

}



func deleteCachedRecord(_ record: CKRecord) {



if record.recordType == Schema.RecordType.topic {



if let index = self.topics.index(where: {$0.record.recordID == record.recordID}) {

self.topics.remove(at: index)

}

}

else if record.recordType == Schema.RecordType.note {



var topic: Topic  = orphanNoteTopic // Default value.



if let topicRef = record[Schema.Note.topic] as? CKReference {

if let index = topics.index(where: {$0.record.recordID == topicRef.recordID}) {

topic = topics[index]

}

}



if let index = topic.notes.index(where: {$0.record.recordID == record.recordID}) {

topic.notes.remove(at: index)

}

}

postNotificationWhenAllOperationsAreFinished(name: .topicCacheDidChange)

}



// Remove the note from its original topic and add it into the new topic if a different topic is picked.

// For peers to better maintain the local cache, we do this by first delete the note, then add a new note.

// Currently saving a public database record with non-nil .parent property will throw server rejection

// error, so we set the .parent value only when current database is not public.

//

func switchNoteTopic(note: Note, orginalTopic: Topic, newTopic: Topic) {



let newNoteRecord = CKRecord(recordType: Schema.RecordType.note, zoneID: zone.zoneID)

newNoteRecord[Schema.Note.title] = note.record[Schema.Note.title]



if newTopic !== orphanNoteTopic {

newNoteRecord[Schema.Note.topic] = CKReference(record: newTopic.record, action: .deleteSelf)



if database.databaseScope != .public {

newNoteRecord.parent = CKReference(record: newTopic.record, action: .none)

}

}



let notificationObject = NSMutableDictionary()

notificationObject.setValue(NotificationReason.switchTopic, forKey: NotificationObjectKey.reason)



let operation = CKModifyRecordsOperation(recordsToSave: [newNoteRecord], recordIDsToDelete: [note.record.recordID])



operation.modifyRecordsCompletionBlock = { (_, _, error) in

guard CloudKitError.share.handle(error: error, operation: .modifyRecords, alert: true) == nil else {return}



if let index = orginalTopic.notes.index(where: {$0.record.recordID == note.record.recordID}) {

orginalTopic.notes.remove(at: index)

}



let newNote = Note(noteRecord:newNoteRecord, database: self.database)

newTopic.notes.append(newNote)

newTopic.sortNotes()



notificationObject.setValue(newNote, forKey: NotificationObjectKey.newNote)

}

operation.database = database

operationQueue.addOperation(operation)

postNotificationWhenAllOperationsAreFinished(name: .topicCacheDidChange, object: notificationObject)

}



func deleteAll() {



let idsToDelete = TopicLocalCache.share.topics.map(){$0.record.recordID}

let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: idsToDelete)

operation.modifyRecordsCompletionBlock = { (records, recordIDs, error) in



guard CloudKitError.share.handle(error: error, operation: .modifyRecords, alert: true) == nil else {return}

self.topics.removeAll()

}

operation.database = database

operationQueue.addOperation(operation)

postNotificationWhenAllOperationsAreFinished(name: .topicCacheDidChange)

}

}
/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 Menu view controller class.
 
 */



import Foundation

import UIKit



class MenuViewController: UIViewController, UIGestureRecognizerDelegate {

// Constants.

//

fileprivate struct Settings {

static let menuWidth: CGFloat = 270.0

static let maxMaskOpacity: CGFloat = 0.6

static let maxMainViewScale: CGFloat = 0.96

static let panBezelWidth: CGFloat = 16.0

}



// Gesture.

//

fileprivate var tapGesture: UITapGestureRecognizer!

fileprivate var panGesture: UIPanGestureRecognizer!



//

fileprivate var maskView = UIView()

fileprivate var mainContainerView = UIView()

fileprivate var menuContainerView = UIView()



var mainViewController: UIViewController!

var menuViewController: UIViewController!



// Prevent clients from calling init other than the convenience one.

//

required public init?(coder aDecoder: NSCoder) {

fatalError("init(coder:) has not been implemented")

}



init(mainViewController: UIViewController, menuViewController: UIViewController) {

super.init(nibName: nil, bundle: nil)

self.mainViewController = mainViewController

self.menuViewController = menuViewController

}



override func viewDidLoad() {

super.viewDidLoad()



mainContainerView = UIView(frame: view.bounds)

mainContainerView.backgroundColor = UIColor.clear

view.insertSubview(mainContainerView, at: 0)



maskView = UIView(frame: view.bounds)

maskView.backgroundColor = UIColor.black

maskView.layer.opacity = 0.0

view.insertSubview(maskView, at: 1)



var menuFrame: CGRect = view.bounds

menuFrame.origin.x = 0.0 - Settings.menuWidth

menuFrame.size.width = Settings.menuWidth

menuContainerView = UIView(frame: menuFrame)

menuContainerView.backgroundColor = UIColor.clear

view.insertSubview(menuContainerView, at: 2)



// Setup main and menu view controller.

//

addChildViewController(mainViewController)

mainViewController.view.frame = mainContainerView.bounds

mainContainerView.addSubview(mainViewController.view)

mainViewController.didMove(toParentViewController: self)



addChildViewController(menuViewController)

menuViewController.view.frame = menuContainerView.bounds

menuContainerView.addSubview(menuViewController.view)

menuViewController.didMove(toParentViewController: self)



tapGesture = UITapGestureRecognizer(target: self, action: #selector(type(of: self).toggleMenu))

tapGesture.delegate = self

view.addGestureRecognizer(tapGesture)



panGesture = UIPanGestureRecognizer(target: self, action: #selector(type(of: self).handlePanGesture(_:)))

panGesture.delegate = self

view.addGestureRecognizer(panGesture)

}



func isMenuHidden() -> Bool {

return menuContainerView.frame.origin.x <= 0.0 - Settings.menuWidth

}



func showMenu(velocity: CGFloat = 0.0) {



view.window?.windowLevel = UIWindowLevelStatusBar + 1

menuViewController.beginAppearanceTransition(isMenuHidden(), animated: true)



let xOffset = fabs(menuContainerView.frame.origin.x)

var duration = Double(velocity != 0.0 ? xOffset / fabs(velocity): 0.4)

duration = Double(fmax(0.2, fmin(0.8, duration)))



var frame = menuContainerView.frame

frame.origin.x = 0.0;



UIView.animate( withDuration: duration, delay: 0.0, options: UIViewAnimationOptions(), animations: { _ in

self.menuContainerView.frame = frame

self.maskView.layer.opacity = Float(Settings.maxMaskOpacity)

self.mainContainerView.transform = CGAffineTransform(scaleX: Settings.maxMainViewScale,

y: Settings.maxMainViewScale)



}) { _ in

self.mainContainerView.isUserInteractionEnabled = false

self.menuViewController.endAppearanceTransition()

}

}



func hideMenu(velocity: CGFloat = 0.0) {



menuViewController.beginAppearanceTransition(isMenuHidden(), animated: true)



let xOffset = Settings.menuWidth - fabs(menuContainerView.frame.origin.x)

var duration = Double(velocity != 0.0 ? xOffset / fabs(velocity): 0.4)

duration = Double(fmax(0.2, fmin(0.8, duration)))



var frame: CGRect = menuContainerView.frame

frame.origin.x = 0.0 - Settings.menuWidth



UIView.animate(withDuration: duration, delay: 0.0, options: UIViewAnimationOptions(), animations: { _ in

self.menuContainerView.frame = frame

self.maskView.layer.opacity = 0.0

self.mainContainerView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)



}) { _ in

self.mainContainerView.isUserInteractionEnabled = true

self.menuViewController.endAppearanceTransition()

}



view.window?.windowLevel = UIWindowLevelNormal

}



func toggleMenu() { isMenuHidden() == false ? hideMenu() : showMenu() }

}



// UIGestureRecognizerDeletate and gesture handler.

//

extension MenuViewController {



private struct States {

static var grState: UIGestureRecognizerState = .ended

static var panBeginAt = CGPoint()

static var initialMenuOrigin = CGPoint()

static func isMenuShownAtStart() -> Bool {return States.initialMenuOrigin.x == 0.0}

}



func handlePanGesture(_ panGesture: UIPanGestureRecognizer) {



if panGesture.state == .began {

guard States.grState == .ended || States.grState == .cancelled

|| States.grState == .failed else {return}



menuViewController.beginAppearanceTransition(!isMenuHidden(), animated: true)

view.window?.windowLevel = UIWindowLevelStatusBar + 1



// Pick up the initial states.

//

States.initialMenuOrigin = menuContainerView.frame.origin

States.panBeginAt = panGesture.translation(in: view)

}

else if panGesture.state == .changed {

guard States.grState == .began || States.grState == .changed else {return}



// Calcuate the x offset, the offset relative to -Settings.menuWidth.

//

let xInView = panGesture.translation(in: view).x

var xOffset = xInView - States.panBeginAt.x



if xOffset > 0.0 {

xOffset = States.isMenuShownAtStart() ? Settings.menuWidth : min(xOffset, Settings.menuWidth)

}

else {

xOffset = max(-Settings.menuWidth, xOffset)

xOffset = States.isMenuShownAtStart() ? Settings.menuWidth + xOffset : xInView

}



// Calculate the new frame for menuContainerView.

//

let newOrigin = CGPoint(x: xOffset - Settings.menuWidth, y: States.initialMenuOrigin.y)

menuContainerView.frame = CGRect(origin: newOrigin, size: menuContainerView.frame.size)



// Calculte the maskView opacity and main view transform based on the ratio.

//

let ratio = xOffset / Settings.menuWidth



maskView.layer.opacity = Float(Settings.maxMaskOpacity * ratio)



let scale = Settings.maxMainViewScale + (1.0 - Settings.maxMainViewScale) * (1.0 - ratio)

mainContainerView.transform = CGAffineTransform(scaleX: scale, y:scale)

}

else if panGesture.state == .ended || panGesture.state == .cancelled {

guard States.grState == .changed else {return}



// Hide menu only when users tend to hide it.

//

let velocity: CGPoint = panGesture.velocity(in: panGesture.view)



if States.isMenuShownAtStart() { // Menu is initially visible.

if panGesture.translation(in: view).x < States.panBeginAt.x {

hideMenu(velocity: velocity.x)

}

}

else {

if panGesture.translation(in: view).x > States.panBeginAt.x {

showMenu(velocity: velocity.x)

}

}

}

States.grState = panGesture.state

}



// MARK: UIGestureRecognizerDeletate.

//

func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {



let point: CGPoint = touch.location(in: view)



if gestureRecognizer == panGesture {

let tuple = view.bounds.divided(atDistance: Settings.panBezelWidth, from: CGRectEdge.minXEdge)

let isPointContained = tuple.slice.contains(point)

return !isMenuHidden() || isPointContained

}

else if gestureRecognizer == tapGesture {

let isPointContained = menuContainerView.frame.contains(point)

return !isMenuHidden() && !isPointContained

}

return true

}

}

/*
 
 Copyright (C) 2017 Rahul Thukral . All Rights Reserved.
 
 See LICENSE.txt for this sample’s licensing information
 
 
 
 Abstract:
 
 Modal classes and protocol for local cache items
 
 */





import Foundation

import CloudKit



// Note: Data modal class.



// Permission control in UI.

// In public and private database, permission is default to .readWrite for the record creator.

// shareDB is different:

// 1. A participant can always remove the participation by presentign a UICloudSharingController

// 2. A participant can change the record content if they have .readWrite permission.

// 3. A participant can add a record into a parent if they have .readWrite permission.

// 4. A participant can remove a record added by themselves from a parent.

// 5. A participant can not remove a root record if they are not the creator.

// 6. Users can not "add" a note if they can't write the topic. (Implemented in MainViewController.numberOfRowsInSection)

//



protocol CacheItem {

var record: CKRecord {get set}

var permission: CKShareParticipantPermission {get set}

}



extension CacheItem {

mutating func setPermission(with shares: [CKShare]) -> Int? {

for (index, share) in shares.enumerated() where record.share?.recordID == share.recordID {

if let participant = share.currentUserParticipant {

permission = participant.permission

return index

}

}

return nil

}

}



// Note: Data modal class.

//

class Note: CacheItem {

var record: CKRecord

var permission = CKShareParticipantPermission.readWrite



// We need the database to setup the default permission.

// Clients can change the permission later, so provide nil as the default value.

//

init(noteRecord: CKRecord, database: CKDatabase? = nil) {

record = noteRecord



if database?.databaseScope == .public, let creatorID = record.creatorUserRecordID,

creatorID.recordName != CKCurrentUserDefaultName {

permission = .readOnly

}

}



func isVisuallyEqual(to noteRecord: CKRecord) -> Bool {

if noteRecord.recordType != record.recordType {

return false

}

let title1 = noteRecord[Schema.Note.title] as? String

let title2 = record[Schema.Note.title] as? String

if title1 != title2 {

return false

}

let topicRef1 = noteRecord[Schema.Note.topic] as? CKReference

let topicRef2 = record[Schema.Note.topic] as? CKReference

if topicRef1?.recordID != topicRef2?.recordID {

return false

}

return true

}

}



// Topic: Data modal class.

//

class Topic: CacheItem {

var record: CKRecord

var permission = CKShareParticipantPermission.readWrite

var notes: [Note]



// We need the database to setup the default permission.

// Clients can change the permission, so provide nil as the default value

//

init(topicRecord: CKRecord, notes: [Note] = [Note](), database: CKDatabase? = nil) {

record = topicRecord



if database?.databaseScope == .public, let creatorID = record.creatorUserRecordID,

creatorID.recordName != CKCurrentUserDefaultName {

permission = .readOnly

}

self.notes = notes

}



func sortNotes() {

notes.sort() { (note0, note1) in

guard let title0 = note0.record[Schema.Note.title] as? String,

let title1 = note1.record[Schema.Note.title] as? String else {return false}

return title0 < title1

}

}



func fetchNotes(from database: CKDatabase, predicate: NSPredicate? = nil, operationQueue: OperationQueue? = nil,

completionHandler: ((_ error: NSError?) -> Void)? = nil) {



let predicate = predicate ?? NSPredicate(format: "%K = %@", Schema.Note.topic, record)



database.fetchRecords(

with: Schema.RecordType.note, predicate: predicate, zoneID: TopicLocalCache.share.zone.zoneID,

operationQueue: operationQueue) { (results, moreComing, error) in



if CloudKitError.share.handle(error: error, operation: .fetchRecords) != nil {

if let completionHandler = completionHandler { completionHandler(error) }

return

}

self.notes = self.notes + results.map(){ Note(noteRecord:$0, database: database) }

if moreComing {return}



self.sortNotes()



if let completionHandler = completionHandler { completionHandler(error) }

}

}



func isVisuallyEqual(to topicRecord: CKRecord) -> Bool {

if topicRecord.recordType != record.recordType {

return false

}

let name1 = topicRecord[Schema.Topic.name] as? String

let name2 = record[Schema.Topic.name] as? String

if name1 != name2 {

return false

}

return true

}

}




/*
CloudKit Share: Building CloudKit local cache and using CloudKit share APIs

Version: 1.0



IMPORTANT:  This Apple software is supplied to you by Rahul Thukral(Apple Employee)

Inc. ("Apple") in consideration of your agreement to the following

terms, and your use, installation, modification or redistribution of

this Apple software constitutes acceptance of these terms.  If you do

not agree with these terms, please do not use, install, modify or

redistribute this Apple software.



In consideration of your agreement to abide by the following terms, and

subject to these terms, Apple grants you a personal, non-exclusive

license, under Apple's copyrights in this original Rahul Thukral software (the

“Rahul Thukral Software"), to use, reproduce, modify and redistribute the Apple

Software, with or without modifications, in source and/or binary forms;

provided that if you redistribute the Rahul Thukral Software in its entirety and

without modifications, you must retain this notice and the following

text and disclaimers in all such redistributions of the Apple Software.

Neither the name, trademarks, service marks or logos of Apple Inc. may

be used to endorse or promote products derived from the Apple Software

without specific prior written permission from Apple.  Except as

expressly stated in this notice, no other rights or licenses, express or

implied, are granted by Apple herein, including but not limited to any

patent rights that may be infringed by your derivative works or by other

works in which the Apple Software may be incorporated.



The Rahul Thukral Software is provided by Apple on an "AS IS" basis.

APPLE

MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION

THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS

FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND

OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.



IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL

OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF

SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS

INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,

MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED

AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),

STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE

POSSIBILITY OF SUCH DAMAGE.




Copyright (C) 2017 Rahul Thukral . All Rights Reserved.

*/
