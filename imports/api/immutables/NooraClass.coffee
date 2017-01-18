
Immutable = require 'immutable'
moment = require 'moment'
{ Facilities } = require '../collections/facilities.coffee'
{ Classes } = require '../collections/classes.coffee'
{ ClassesSchema } = require '../collections/classes.coffee'

BaseNooraClass = Immutable.Record {
  location: '',
  name: '',
  date: moment().format("YYYY-MM-DD"),
  start_time: null,
  end_time: null,
  total_patients: 0,
  total_family_members: 0,
  educators: Immutable.List(),
  facility_salesforce_id: '',
  condition_operation_salesforce_id: '',
  attendance_report_salesforce_id: '',
  facility_name: '',
  attendees: Immutable.List()
}

class NooraClass extends BaseNooraClass
  constructor: ( properties )->
    super Object.assign({}, properties, {
      attendees: Immutable.List properties && properties.attendees,
      educators: Immutable.List properties && properties.educators
    });

  setClassName: ->
    return this.set "name", "#{ this.facility_name }: #{ this.location } - #{ this.date }, #{this.start_time} to #{this.end_time}"

  save: ->
    nooraClass = this
    if nooraClass.name == ''
      nooraClass = nooraClass.setClassName()
      console.log "Saving this class"
      console.log nooraClass.toJS()
    return new Promise ( resolve, reject )->
      Meteor.call "nooraClass.upsert", nooraClass.toJS(), ( error, results )->
        if error
          reject error
        else
          nooraClassDoc = Classes.findOne({ name: nooraClass.name })
          Meteor.call "syncWithSalesforce", nooraClassDoc
          resolve nooraClass

if Meteor.isServer
  { SalesforceInterface } = require '../salesforce/SalesforceInterface.coffee'

  Meteor.methods
    "syncWithSalesforce": ( classDoc )->
      console.log "Syncing with salesforce"
      toSalesforce = new SalesforceInterface()
      if classDoc.attendance_report_salesforce_id != '' and classDoc.attendees.length > 0
        promise = toSalesforce.exportAttendees(classDoc)
        promise.then(( attendees )->
          console.log "Success exporting attendees"
          classDoc.attendees = attendees
          classDoc.export_attendees_error = false
          Classes.update { name: classDoc.name }, {$set: classDoc }
          console.log Classes.findOne { name: classDoc.name }
        , ( err )->
          Classes.update { name: classDoc.name }, {$set: { export_attendees_error: true }}
          console.log "error exporting attendees"
          console.log err
        )
      else
        promise = toSalesforce.exportClass(classDoc);
        promise.then( (id)->
          console.log "Success exporting class!! "
          classDoc.attendance_report_salesforce_id = id
          Classes.update { name: classDoc.name }, {$set: classDoc }
          console.log classDoc.attendance_report_salesforce_id
          return toSalesforce.exportClassEducators(classDoc)
        ).then(( educators )->
          console.log "Success exporting class educator objects"
          classDoc.educators = educators
          classDoc.export_class_error = false
          Classes.update { name: classDoc.name }, {$set: classDoc }
          console.log Classes.findOne { name: classDoc.name }
        , (err)->
          console.log "There was an error syncing with salesforce"
          console.log err
          Classes.update { name: classDoc.name }, {$set: { export_class_error: true }}
        )

    "nooraClass.upsert": ( nooraClass )->
      facility = Facilities.findOne { name: nooraClass.facility_name }
      if not facility
        throw new Meteor.Error "Facility Does Not Exist", "That facility is not in the database. Ensure that the facility exists in Salesforce and has been synced with the app"
      nooraClass.facility_salesforce_id = facility.salesforce_id
      ClassesSchema.clean(nooraClass)
      ClassesSchema.validate(nooraClass);
      return Classes.upsert { name: nooraClass.name }, { $set: nooraClass }

module.exports.NooraClass = NooraClass
