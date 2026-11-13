#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: "2026-11-12",
  title: "2026-11-12",
  kind: "daily",
  date: "2026-11-12",
  tags: ("journal",),
)

= 2026-11-12

- Student 20231234 booked an appointment with me in the lab, he asked to use #tylog.ref-note("TL-0102")[ESP32 DevKit] and Soldering station A. he has problems with ESP32 library
#tylog.task(
  id: "loan-301adcb5",
  text: "for José Graça class student asked to use the yellow Quest 3",
  assignees: ("lab-person-7",),
  properties: ("loan": true, "equipment": ("TL-0201",), "borrower": "José Graça", "clocked": (("2026-11-12T21:51:31.921818", "2026-11-12T23:19:16.685286Z"),),),
  status: "done",
)
#tylog.task(
  id: "loan-314c2405",
  text: "Студент 20239876 взял QUEST 3 [2] домой до пятницы",
  due: "2026-11-13",
  properties: ("loan": true, "purpose": "take-home", "equipment": ("TL-0202",), "borrower": "Студент 20239876", "topic": "QUEST 3 [2]", "clocked": (("2026-11-12T21:24:05.021222", none),),),
  status: "doing",
)
