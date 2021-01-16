import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:color_convert/color_convert.dart';
import 'package:instiapp/schedule/classes/courseClass.dart';
import 'package:instiapp/schedule/classes/eventClass.dart';
import 'package:instiapp/schedule/classes/examClass.dart';
import 'package:instiapp/data/dataContainer.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:instiapp/utilities/globalFunctions.dart';
import 'package:http/io_client.dart';
import 'package:http/http.dart';
import 'package:connectivity/connectivity.dart';
import 'dart:developer';

class ScheduleContainer {
  List<Course> allCourses = [];
  List allCoursesRows = [];

  // 1 = monday, 2 = tuesday and so on. defined in datetime package
  Map<int, List<Course>> enrolledCourses = {};
  Map<int, List<Event>> events = {};
  Map<int, List<Exam>> exams = {};

  // Sorted Map for all Courses + Events + Exams
  Map<int, List<dynamic>> schedule = {};

  //All courses in a single row for deleting purpose
  List<List> allEnrolledSlots = [];

  //Current two events
  List<dynamic> twoEvents = [];

  static Map<String, List<DateTime>> slots = {};

  static List<DateTime> getTimeFromSlot(String slot) {
    if (slots[slot] == null) {
      return [DateTime(2000, 1, 1), DateTime(2000, 1, 1)];
    }
    return slots[slot];
  }

  ScheduleContainer() {
    getSlots();
    for (int i = 1; i < 8; i++) {
      enrolledCourses[i] = [];
      events[i] = [];
      exams[i] = [];
    }
  }

  void getData() {
    // check if there is a cached file that has enrolledCourses
    getEnrolledCourses();
    // load all courses from sheets
    getAllCourses();
    // load events from calendar api
    reloadEvents();
    // load exams from sheets
  }

  void buildData() {
    buildSchedule();
    buildTwoEvents();
  }

  //------------------------------------BUILD AND SORT SCHEDULE--------------------------------------------//
  void buildSchedule() {
    schedule = {};
    for (int i = 1; i < 8; i++) {
      schedule[i] = [];
    }

    for (int i = 1; i < 8; i++) {
      enrolledCourses[i].forEach((Course course) {
        schedule[i].add(course);
      });
      events[i].forEach((Event event) {
        schedule[i].add(event);
      });
      exams[i].forEach((Exam exam) {
        schedule[i].add(exam);
      });

      schedule[i].sort((a, b) => a.startTime.compareTo(b.startTime));
    }
  }

  //Return currently scheduled two events to show on Home Screen
  void buildTwoEvents() {
    twoEvents = [];
    DateTime currentTime = DateTime.now();
    if (schedule != null && schedule[DateTime.now().weekday] != null) {
      schedule[DateTime.now().weekday].forEach((event) {
        if (twoEvents.length < 2) {
          if (event.endTime.isAfter(currentTime) ||
              event.startTime.isAfter(currentTime)) {
            twoEvents.add(event);
          }
        }
      });
    }
  }

  //------------------------------------COURSES--------------------------------------------//

  static void getSlots() {
    sheet.getData('slots!A:F').listen((data) {
      //remove useless rows
      data.removeAt(0);
      data.removeAt(0);

      data.forEach((var row) {
        List times = row[0].split('-');
        times[0] = times[0].trim();
        times[1] = times[1].trim();

        for (int i = 1; i < 6; i++) {
          slots[row[i]] = [
            DateTime(2021, 1, 3 + i, int.parse(times[0].split(':')[0]),
                int.parse(times[0].split(':')[1])),
            DateTime(2021, 1, 3 + i, int.parse(times[1].split(':')[0]),
                int.parse(times[1].split(':')[1]))
          ];
        }
      });
    });
  }

  List parseSlotString(String slotString) {
    List list = [];
    slotString = slotString.replaceAll(' ', '');
    if (slotString != '-') {
      list = slotString.split(',');
      // print(list);
      List newList = [];
      list.forEach((var clubbedString) {
        clubbedString = clubbedString.split('+');
        if (clubbedString.length == 1) {
          if (clubbedString[0].length == 1) {
            var keys = ScheduleContainer.slots.keys.toList();
            for (int i = 0; i < keys.length; i++) {
              if (keys[i][0] == clubbedString[0][0]) {
                newList.add(keys[i]);
              }
            }
          } else {
            newList.add(clubbedString[0]);
          }
        } else {
          newList.add(clubbedString);
        }
      });

      list = newList;
    }
    return list;
  }

  void unEnrollCourse(int index, int weekday, bool unEnroll) {
    if (unEnroll) {
      Course unEnrollCourse = enrolledCourses[weekday][index];
      for (int i = 1; i < 8; i++) {
        int idx = enrolledCourses[i]
            .indexWhere((Course course) => course.code == unEnrollCourse.code);
        while (idx != -1) {
          enrolledCourses[i].removeAt(idx);
          idx = enrolledCourses[i].indexWhere(
              (Course course) => course.code == unEnrollCourse.code);
        }
      }
      getAllEnrolledCourses();
      storeEnrolledCourses();
    } else {
      enrolledCourses[weekday].removeAt(index);
      getAllEnrolledCourses();
      storeEnrolledCourses();
    }
  }

  void enrollCourseFromIndex(int index, bool value) {
    if (value == true) {
      log('Enrolling course #$index', name: 'COURSES');
      var row = allCoursesRows[index];
      List lecSlots = parseSlotString(row[11]);
      List tutSlots = parseSlotString(row[12]);
      List labSlots = parseSlotString(row[13]);
      lecSlots.forEach((slot) {
        Course course = Course.fromSheetRow(row, slot, 0, index);
        if (!enrolledCourses[course.startTime.weekday].any(
            (_course) => _course.code == course.code && _course.slot == slot)) {
          enrolledCourses[course.startTime.weekday].add(course);
        }
      });
      tutSlots.forEach((slot) {
        Course course = Course.fromSheetRow(row, slot, 1, index);
        if (!enrolledCourses[course.startTime.weekday].any(
            (_course) => _course.code == course.code && _course.slot == slot)) {
          enrolledCourses[course.startTime.weekday].add(course);
        }
      });
      labSlots.forEach((slot) {
        Course course = Course.fromSheetRow(row, slot, 2, index);
        if (!enrolledCourses[course.startTime.weekday].any(
            (_course) => _course.code == course.code && _course.slot == slot)) {
          enrolledCourses[course.startTime.weekday].add(course);
        }
      });
    }
  }

  Future getAllCourses() async {
    await sheet.getDataOnline('timetable!A:Q').then((data) {
      allCourses = [];
      allCoursesRows = [];
      data.removeAt(0);
      int i = 0;
      data.forEach((var row) {
        allCourses.add(Course.fromSheetRow(row, 'UNEXPANDED', 0, i));
        i += 1;
        allCoursesRows.add(row);
      });
      log("Loaded ${allCourses.length} courses from ${data.length} rows",
          name: 'COURSES');
    });
  }

  void getEnrolledCourses() {
    for (int i = 1; i < 8; i++) {
      enrolledCourses[i] = [];
    }
    getCachedData('enrolledCourses').then((data) {
      if (data != null) {
        //In cache the data is stored as list of list so list[i] is courses of weekday = i + 1
        for (int i = 0; i < 7; i++) {
          int index = 0;
          List courses = data[i];
          courses.forEach((jsonCourse) {
            var col = convert.hsv.rgb(10 * index++ % 360, 80, 80);
            Map course = jsonDecode(jsonCourse);
            enrolledCourses[i + 1].add(Course(
                code: course['code'],
                name: course['name'],
                ltpc: [
                  course['ltpc'][0],
                  course['ltpc'][1],
                  course['ltpc'][2],
                  course['ltpc'][3]
                ],
                startTime: DateTime(
                    course['startTime'][0],
                    course['startTime'][1],
                    course['startTime'][2],
                    course['startTime'][3],
                    course['startTime'][4]),
                endTime: DateTime(
                    course['endTime'][0],
                    course['endTime'][1],
                    course['endTime'][2],
                    course['endTime'][3],
                    course['endTime'][4]),
                instructors: course['instructors'],
                slotType: course['slotType'],
                minor: course['minor'],
                cap: course['cap'],
                prerequisite: course['prerequisite'],
                enrolled: true,
                slot: course['slot'],
                color: Color.fromARGB(100, col[0], col[1], col[2])));
          });
        }
      }

      log("Loaded enrolled courses from Cache", name: 'COURSES');
    });
  }

  void storeEnrolledCourses() {
    //Will be stored as List of List
    List<List> saveToCache = [[], [], [], [], [], [], []];

    enrolledCourses.forEach((int day, List<Course> courses) {
      courses.forEach((Course course) {
        saveToCache[day - 1].add(course.toJson());
      });
    });

    storeCachedData('enrolledCourses', saveToCache).then((value) {
      buildData();
      log("Stored enrolled courses to Cache", name: 'COURSES');
    });
  }

  //Function to get all the enrolled course slots in a single list for deleting purpose
  getAllEnrolledCourses() {
    allEnrolledSlots = [];
    enrolledCourses.forEach((int day, List<Course> dayCourses) {
      int index = 0;
      dayCourses.forEach((Course course) {
        allEnrolledSlots.add([course, day, index++]);
      });
    });
  }

  //------------------------------------CALENDAR EVENTS--------------------------------------------//

  Future reloadEvents() async {
    for (int i = 1; i < 8; i++) {
      events[i] = [];
    }
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult != ConnectivityResult.none) {
      dataContainer.auth.gSignIn.signInSilently().then((value) async {
        final authHeaders =
            await dataContainer.auth.gSignIn.currentUser.authHeaders;
        final httpClient = GoogleHttpClient(authHeaders);
        getEventsOnline(httpClient);
      });
    }
  }

  Future getEventsOnline(httpClient) async {
    var eventData =
        await calendar.CalendarApi(httpClient).events.list('primary');
    List<calendar.Event> tempEvents = [];
    tempEvents.addAll(eventData.items);
    makeListWithoutRepetitionEvent(tempEvents);
  }

  void makeListWithoutRepetitionEvent(List<calendar.Event> tempEvents) {
    List<calendar.Event> withoutRepeat = [];

    tempEvents.forEach((calendar.Event event) {
      bool notHave = true;
      withoutRepeat.forEach((calendar.Event _event) {
        if (_event.id == event.id) {
          notHave = false;
        }
      });
      if (notHave &&
          event != null &&
          event.start != null &&
          event.start.dateTime != null &&
          event.start.dateTime.year == DateTime.now().year &&
          event.start.dateTime.month == DateTime.now().month &&
          event.start.dateTime.day == DateTime.now().day) {
        withoutRepeat.add(event);
      }
    });

    for (int i = 1; i < 8; i++) {
      events[i] = [];
    }

    withoutRepeat.forEach((calendar.Event event) {
      if (event != null) {
        events[DateTime.now().weekday].add(Event(
            startTime: (event.start != null && event.start.dateTime != null)
                ? event.start.dateTime.toLocal()
                : DateTime(2021, 1, 1, 1),
            endTime: (event.end != null && event.end.dateTime != null)
                ? event.end.dateTime.toLocal()
                : DateTime(2021, 1, 1, 2),
            name: (event.description != null) ? event.description : "",
            host: (event.creator != null && event.creator.displayName != null)
                ? event.creator.displayName
                : "",
            link: (event.htmlLink != null)
                ? event.htmlLink
                : "" //TODO: Have to check how to obtain link from calendar.event object
            ));
      }
    });

    log("Loaded ${withoutRepeat.length} calendar events", name: 'EVENTS');
  }
}

//For getting headers to fetch Calendar Events
class GoogleHttpClient extends IOClient {
  Map<String, String> _headers;

  GoogleHttpClient(this._headers) : super();

  @override
  Future<StreamedResponse> send(BaseRequest request) =>
      super.send(request..headers.addAll(_headers));

  @override
  Future<Response> head(Object url, {Map<String, String> headers}) =>
      super.head(url, headers: headers..addAll(_headers));
}
