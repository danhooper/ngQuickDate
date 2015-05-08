#
# ngQuickDate
# originally by Adam Albrecht
# http://adamalbrecht.com
# modified by Ken Wang
#
# Source Code: https://github.com/gildorwang/ngQuickDate
#
# Compatible with Angular 1.3.0+
#

app = angular.module("ngQuickDate", [])

app.provider "ngQuickDateDefaults", ->
  {
    options: {
      dateFormat: 'M/d/yyyy'
      timeFormat: 'h:mm a'
      labelFormat: null
      placeholder: 'Click to Set Date'
      hoverText: null
      buttonIconHtml: null
      closeButtonHtml: '&times;'
      nextLinkHtml: 'Next &rarr;'
      prevLinkHtml: '&larr; Prev'
      disableTimepicker: false
      disableClearButton: false
      defaultTime: null
      dayAbbreviations: ["Su", "M", "Tu", "W", "Th", "F", "Sa"],
      dateFilter: null
      timezone: null
      debug: false
      parseDateFunction: (str) ->
        seconds = Date.parse(str)
        if isNaN(seconds)
          return null
        else
          new Date(seconds)
    }
    $get: ->
      @options

    set: (keyOrHash, value) ->
      if typeof(keyOrHash) == 'object'
        for k, v of keyOrHash
          @options[k] = v
      else
        @options[keyOrHash] = value
  }

app.directive "quickDatepicker", ['ngQuickDateDefaults', '$filter', '$sce', '$log'
(ngQuickDateDefaults, $filter, $sce, $log) ->
  restrict: "E"
  require: "?ngModel"
  scope:
    dateFilter: '=?'
    disableTimepicker: '=?'
    disableClearButton: '=?'
    timezone: '=?'
    onChange: "&"
    required: '@'
    debug: '=?'

  replace: true
  link: (scope, element, attrs, ngModelCtrl) ->
    emptyTime = '00:00:00'
    debugLog = (message) -> if scope.debug then $log.debug "[quickdate] " + message
    templateDate = new Date("2015-01-01T12:00Z")

    # INITIALIZE VARIABLES AND CONFIGURATION
    # ================================
    initialize = ->
      setConfigOptions() # Setup configuration variables
      scope.toggleCalendar(false) # Make sure it is closed initially
      scope.weeks = [] # Nested Array of visible weeks / days in the popup
      scope.inputDate = null # Date inputted into the date text input field
      scope.inputTime = null # Time inputted into the time text input field
      scope.invalid = true
      if typeof(attrs.initValue) == 'string'
        ngModelCtrl.$setViewValue(attrs.initValue)
      setCalendarDate()
      refreshView()

    scope.getDatePlaceholder = () ->
      dateToString(templateDate, scope.getDateFormat())

    scope.getTimePlaceholder = () ->
      dateToString(templateDate, scope.getTimeFormat())

    # Use the ISO formats if timezone is UTC.
    # This is necessary to ensure the date string is parsed in correct timezone.
    scope.getDateFormat = () ->
      if isUTC()
        "yyyy-MM-dd"
      else
        scope.dateFormat

    scope.getTimeFormat = () ->
      if isUTC()
        "HH:mm:ss"
      else
        scope.timeFormat

    scope.getLabelFormat = () ->
      return scope.labelFormat ?
        if scope.disableTimepicker
          scope.getDateFormat()
        else
          scope.getDateFormat() + " " + scope.getTimeFormat()

    # Copy various configuration options from the default configuration to scope
    setConfigOptions = ->
      for key, value of ngQuickDateDefaults
        if key.match(/[Hh]tml/)
          scope[key] = $sce.trustAsHtml(ngQuickDateDefaults[key] || "")
        else if not scope[key]?
          scope[key] = attrs[key] ? ngQuickDateDefaults[key]

      if attrs.iconClass && attrs.iconClass.length
        scope.buttonIconHtml = $sce.trustAsHtml("<i ng-show='iconClass' class='#{attrs.iconClass}'></i>")

    # VIEW SETUP
    # ================================

    # This code listens for clicks both on the entire document and the popup.
    # If a click on the document is received but not on the popup, the popup
    # should be closed
    datepickerClicked = false
    window.document.addEventListener 'click', (event) ->
      if scope.calendarShown && ! datepickerClicked
        scope.toggleCalendar(false)
        scope.$apply()
      datepickerClicked = false

    angular.element(element[0])[0].addEventListener 'click', (event) ->
      datepickerClicked = true

    # SCOPE MANIPULATION Methods
    # ================================

    # Refresh the calendar, the input dates, and the button date
    refreshView = ->
      date = if ngModelCtrl.$modelValue then parseDateString(ngModelCtrl.$modelValue) else null
      setupCalendarView()
      setInputFieldValues(date)
      scope.mainButtonStr = if date then dateToString(date, scope.getLabelFormat()) else scope.placeholder
      scope.invalid = ngModelCtrl.$invalid

    # Set the values used in the 2 input fields
    setInputFieldValues = (val) ->
      if val?
        scope.inputDate = dateToString(val, scope.getDateFormat())
        scope.inputTime = dateToString(val, scope.getTimeFormat())
      else
        scope.inputDate = null
        scope.inputTime = null

    # Set the date that is used by the calendar to determine which month to show
    # Defaults to the current month
    setCalendarDate = (val=null) ->
      d = if val? then new Date(val) else new Date()
      if (d.toString() == "Invalid Date")
        d = new Date()
      setDate(d, 1)
      scope.calendarDate = d

    # Setup the data needed by the table that makes up the calendar in the popup
    # Uses scope.calendarDate to decide which month to show
    setupCalendarView = ->
      offset = getDay(scope.calendarDate)
      daysInMonth = getDaysInMonth(getFullYear(scope.calendarDate), getMonth(scope.calendarDate))
      numRows = Math.ceil((offset + daysInMonth) / 7)
      weeks = []
      curDate = new Date(scope.calendarDate)
      setDate(curDate, getDate(curDate) + (offset * -1))
      for row in [0..(numRows-1)]
        weeks.push([])
        for day in [0..6]
          d = new Date(curDate)
          setTime(d, emptyTime)
          selected = ngModelCtrl.$modelValue && d && datesAreEqual(d, ngModelCtrl.$modelValue)
          today = datesAreEqual(d, new Date())
          weeks[row].push({
            date: d
            selected: selected
            disabled: if (typeof(scope.dateFilter) == 'function') then !scope.dateFilter(d) else false
            other: getMonth(d) != getMonth(scope.calendarDate)
            today: today
          })
          setDate(curDate, getDate(curDate) + 1)

      scope.weeks = weeks

    # PARSERS AND FORMATTERS
    # =================================
    # When the model is set from within the datepicker, this will be run
    # before passing it to the model.
    ngModelCtrl.$parsers.push((viewVal) ->
      if scope.required && !viewVal?
        ngModelCtrl.$setValidity('required', false)
        null
      else if angular.isDate(viewVal)
        ngModelCtrl.$setValidity('required', true)
        viewVal
      else if angular.isString(viewVal)
        ngModelCtrl.$setValidity('required', true)
        scope.parseDateFunction(viewVal)
      else
        null
    )

    # When the model is set from outside the datepicker, this will be run
    # before passing it to the datepicker
    ngModelCtrl.$formatters.push((modelVal) ->
      if angular.isDate(modelVal)
        modelVal
      else if angular.isString(modelVal)
        scope.parseDateFunction(modelVal)
      else
        undefined
    )

    # HELPER METHODS
    # =================================
    isUTC = () -> scope.timezone is "UTC"

    getDate = (date) -> if isUTC() then date.getUTCDate() else date.getDate()
    getDay = (date) -> if isUTC() then date.getUTCDay() else date.getDay()
    getFullYear = (date) -> if isUTC() then date.getUTCFullYear() else date.getFullYear()
    getHours = (date) -> if isUTC() then date.getUTCHours() else date.getHours()
    getMilliseconds = (date) -> if isUTC() then date.getUTCMilliseconds() else date.getMilliseconds()
    getMinutes = (date) -> if isUTC() then date.getUTCMinutes() else date.getMinutes()
    getMonth = (date) -> if isUTC() then date.getUTCMonth() else date.getMonth()
    getSeconds = (date) -> if isUTC() then date.getUTCSeconds() else date.getSeconds()

    setDate = (date, val) -> if isUTC() then date.setUTCDate(val) else date.setDate(val)
    setFullYear = (date, val) -> if isUTC() then date.setUTCFullYear(val) else date.setFullYear(val)
    setHours = (date, val) -> if isUTC() then date.setUTCHours(val) else date.setHours(val)
    setMilliseconds = (date, val) -> if isUTC() then date.setUTCMilliseconds(val) else date.setMilliseconds(val)
    setMinutes = (date, val) -> if isUTC() then date.setUTCMinutes(val) else date.setMinutes(val)
    setMonth = (date, val) -> if isUTC() then date.setUTCMonth(val) else date.setMonth(val)
    setSeconds = (date, val) -> if isUTC() then date.setUTCSeconds(val) else date.setSeconds(val)
    setTime = (date, val) ->
      parts = (val ? emptyTime).split(':')
      setHours(date, parts[0] ? 0)
      setMinutes(date, parts[1] ? 0)
      setSeconds(date, parts[2] ? 0)
      return date

    addMonth = (date, val) -> new Date(setMonth(new Date(date), getMonth(date) + val))

    dateToString = (date, format) ->
      $filter('date')(date, format, scope.timezone)

    stringToDate = (date) ->
      if typeof date == 'string'
        parseDateString(date)
      else
        date

    parseDateString = ngQuickDateDefaults.parseDateFunction

    combineDateAndTime = (date, time) ->
      if isUTC()
        "#{date}T#{time}Z"
      else
        "#{date} #{time}"

    datesAreEqual = (d1, d2, compareTimes=false) ->
      if compareTimes
        (d1 - d2) == 0
      else
        d1 = stringToDate(d1)
        d2 = stringToDate(d2)
        return d1 && d2 &&
              (getFullYear(d1) == getFullYear(d2)) &&
              (getMonth(d1) == getMonth(d2)) &&
              (getDate(d1) == getDate(d2))

    datesAreEqualToMinute = (d1, d2) ->
      return false unless d1 && d2
      return parseInt(d1.getTime() / 60000) is parseInt(d2.getTime() / 60000)

    getDaysInMonth = (year, month) ->
      [31, (if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) then 29 else 28), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month]

    # Executes a function one time per N milliseconds (wait)
    debounce = (func, wait) ->
      timeout = args = context = timestamp = result = null
      later = ->
        last = +new Date() - timestamp

        if last < wait && last > 0
          timeout = setTimeout(later, wait - last)
        else
          timeout = null

      return ->
        context = this
        args = arguments
        timestamp = +new Date()
        if !timeout
          timeout = setTimeout(later, wait)
          result = func.apply(context, args)
          context = args = null

        return result

    # DATA WATCHES
    # ==================================

    # Called when the model is updated from outside the datepicker
    ngModelCtrl.$render = ->
      setCalendarDate(ngModelCtrl.$viewValue)
      refreshView()

    # Called when the model is updated from inside the datepicker,
    # either by clicking a calendar date, setting an input, etc
    ngModelCtrl.$viewChangeListeners.unshift ->
      setCalendarDate(ngModelCtrl.$viewValue)
      refreshView()
      if scope.onChange
        scope.onChange()

    # When the popup is toggled open, select the date input
    scope.$watch 'calendarShown', (newVal, oldVal) ->
      if newVal
        dateInput = angular.element(element[0].querySelector(".quickdate-date-input"))[0]
        dateInput.select()
        refreshView()

    # When the timezone is changed, refresh the view
    scope.$watch 'timezone', (newVal, oldVal) ->
      return if newVal is oldVal
      ngModelCtrl.$render()

    # When the option disableTimepicker is changed, refresh the view
    scope.$watch 'disableTimepicker', (newVal, oldVal) ->
      return if newVal is oldVal
      refreshView()


    # VIEW ACTIONS
    # ==================================
    scope.toggleCalendar = debounce(
      (show) ->
        if isFinite(show)
          scope.calendarShown = show
        else
          scope.calendarShown = not scope.calendarShown
      150
    )

    # Select a new model date. This is called in 3 situations:
    #   * Clicking a day on the calendar, which calls the `selectDateWithMouse` method, which calls this method.
    #   * Changing the date or time inputs, which calls the `selectDateFromInput` method, which calls this method.
    #   * The clear button is clicked.
    scope.selectDate = (date, closeCalendar=true) ->
      debugLog "selectDate: #{date?.toISOString()}"
      changed = (!ngModelCtrl.$viewValue && date) ||
                (ngModelCtrl.$viewValue && !date) ||
                (
                  (date && ngModelCtrl.$viewValue) &&
                  (date.getTime() != ngModelCtrl.$viewValue.getTime())
                )
      if typeof(scope.dateFilter) == 'function' && !scope.dateFilter(date)
        return false
      ngModelCtrl.$setViewValue(date)
      if closeCalendar
        scope.toggleCalendar(false)
      true

    scope.selectDateWithMouse = (date) ->
      # change the input date
      scope.inputDate = dateToString(date, scope.getDateFormat())
      # close the calendar only when the time picker is disabled
      scope.selectDateFromInput(scope.disableTimepicker)

    # This is triggered when the date or time inputs have a blur or enter event.
    scope.selectDateFromInput = (closeCalendar=false) ->
      try
        tmpDate = parseDateString(combineDateAndTime(scope.inputDate, scope.defaultTime || emptyTime))
        if not tmpDate?
          throw new Error 'Invalid Date'
        if not scope.disableTimepicker and scope.inputTime?.length
          tmpTime = if scope.disableTimepicker
            emptyTime
          else
            scope.inputTime
          tmpDateAndTime = parseDateString(combineDateAndTime(scope.inputDate, tmpTime))
          if not tmpDateAndTime?
            throw new Error 'Invalid Time'
          tmpDate = tmpDateAndTime
        unless datesAreEqualToMinute(ngModelCtrl.$viewValue, tmpDate)
          if !scope.selectDate(tmpDate, false)
            throw new Error 'Invalid Date'

        if closeCalendar
          scope.toggleCalendar(false)

        scope.inputDateErr = false
        scope.inputTimeErr = false

      catch err
        if err.message is 'Invalid Date'
          scope.inputDateErr = true
        else if err.message is 'Invalid Time'
          scope.inputTimeErr = true

    # When tab is pressed from the date input and the timepicker
    # is disabled, close the popup
    scope.onDateInputTab = ->
      if scope.disableTimepicker
        scope.toggleCalendar(false)
      true

    # When tab is pressed from the time input, close the popup
    scope.onTimeInputTab = ->
      scope.toggleCalendar(false)
      true

    # View the next and previous months in the calendar popup
    scope.nextMonth = ->
      setCalendarDate(addMonth(scope.calendarDate, 1))
      refreshView()
    scope.prevMonth = ->
      setCalendarDate(addMonth(scope.calendarDate, -1))
      refreshView()

    # Set the date model to null
    scope.clear = ->
      scope.selectDate(null, true)

    initialize()

  # TEMPLATE
  # ================================================================
  templateUrl: (elem, attrs) ->
    attrs.template || 'ngQuickDate/ngQuickDate.tpl.html'

]

app.run ['$templateCache',
  ($templateCache) ->
    $templateCache.put 'ngQuickDate/ngQuickDate.tpl.html', """
            <div class='quickdate'>
              <a href='' ng-focus='toggleCalendar()' ng-click='toggleCalendar()'
                  class='quickdate-button' title='{{hoverText}}'>\
                <div ng-hide='iconClass' ng-bind-html='buttonIconHtml'></div>\
                {{mainButtonStr}}\
              </a>
              <div class='quickdate-popup' ng-class='{open: calendarShown}'>
                <a href='' tabindex='-1' class='quickdate-close' ng-click='toggleCalendar()'>
                  <div ng-bind-html='closeButtonHtml'></div>
                </a>
                <div class='quickdate-text-inputs'>
                  <div class='quickdate-input-wrapper'>
                    <label>Date</label>
                    <input class='quickdate-date-input' ng-class="{'ng-invalid': inputDateErr}"
                           name='inputDate' type='text' ng-model='inputDate'
                           placeholder='{{ getDatePlaceholder() }}'
                           ng-enter="selectDateFromInput(true)"
                           ng-blur="selectDateFromInput(false)"
                           on-tab='onDateInputTab()' />
                  </div>
                  <div class='quickdate-input-wrapper' ng-hide='disableTimepicker'>
                    <label>Time</label>
                    <input class='quickdate-time-input'
                           ng-class="{'ng-invalid': inputTimeErr}"
                           name='inputTime'
                           type='text'
                           ng-model='inputTime'
                           placeholder='{{ getTimePlaceholder() }}'
                           ng-enter="selectDateFromInput(true)"
                           ng-blur="selectDateFromInput(false)"
                           on-tab='onTimeInputTab()'>
                  </div>
                </div>
                <div class='quickdate-calendar-header'>
                  <a href='' class='quickdate-prev-month quickdate-action-link' tabindex='-1' ng-click='prevMonth()'>
                    <div ng-bind-html='prevLinkHtml'></div>
                  </a>
                  <span class='quickdate-month'>{{calendarDate | date:'MMMM yyyy'}}</span>
                  <a href='' class='quickdate-next-month quickdate-action-link' ng-click='nextMonth()' tabindex='-1' >
                    <div ng-bind-html='nextLinkHtml'></div>
                  </a>
                </div>
                <table class='quickdate-calendar'>
                  <thead>
                    <tr>
                      <th ng-repeat='day in dayAbbreviations'>{{day}}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr ng-repeat='week in weeks'>
                      <td ng-mousedown='selectDateWithMouse(day.date)'
                          ng-click='$event.preventDefault()'
                          ng-class='{"other-month": day.other, "disabled-date": day.disabled, "selected": day.selected, "is-today": day.today}'
                          ng-repeat='day in week'>{{day.date | date:'d':timezone}}</td>
                    </tr>
                  </tbody>
                </table>
                <div class='quickdate-popup-footer'>
                  <a href='' class='quickdate-clear' tabindex='-1' ng-hide='disableClearButton' ng-click='clear()'>Clear</a>
                </div>
              </div>
            </div>
            """
]

app.directive 'ngEnter', ->
  (scope, element, attr) ->
    element.bind 'keydown keypress', (e) ->
      if (e.which is 13)
        scope.$apply(attr.ngEnter)
        e.preventDefault()

app.directive 'onTab', ->
  restrict: 'A',
  link: (scope, element, attr) ->
    element.bind 'keydown keypress', (e) ->
      if (e.which is 9) && !e.shiftKey
        scope.$apply(attr.onTab)
