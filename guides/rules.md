# Rules

Every holiday in dayoff's data is a rule string, the grammar of [date-holidays](https://github.com/commenthol/date-holidays/blob/master/docs/specification.md). This page describes it as dayoff implements it, with the rule strings the data actually uses. `Dayoff.rules/2` shows the rules of any country, state or region, and `Dayoff.Parser.parse!/1` shows how a rule tokenizes.

A rule starts with something that produces a date for a year, followed by clauses that move it, filter it, give it a time or a duration, or limit the years it applies to.

## Dates

| Rule | Meaning |
|------|---------|
| `01-01` | January 1st, every year |
| `2015-10-09` | October 9th 2015 only |
| `February` | February 1st, the anchor for "1st Monday in February" style rules |
| `easter -2` | Two days before Easter Sunday (Good Friday), `easter 1` is Easter Monday |
| `orthodox 1` | Relative to Orthodox Easter |
| `julian 12-25` | December 25th of the Julian calendar (Orthodox Christmas) |
| `1 Shawwal` | A day in the Hijri calendar, month names as upstream spells them: Muharram, Safar, Rabi al-awwal, Rabi al-thani, Jumada al-awwal, Jumada al-thani, Rajab, Shaban, Ramadan, Shawwal, Dhu al-Qidah, Dhu al-Hijjah |
| `14 AdarII` | A day in the Hebrew calendar: Nisan, Iyyar, Sivan, Tamuz, Av, Elul, Tishrei, Cheshvan, Kislev, Tevet, Shvat, Adar, AdarII |
| `1 Farvardin` | A day in the Jalaali (Persian) calendar |
| `chinese 01-0-01` | Lunar month 1, not a leap month, day 1: Chinese New Year. `korean` and `vietnamese` use their own calendars. Day 0 is the eve. |
| `chinese 5-01 solarterm` | Day 1 of the 5th solar term, Qingming |
| `bengali-revised 1-1` | Pohela Boishakh, the Bengali new year |
| `march equinox in +09:00` | The equinox or solstice date in a timezone, `june solstice in America/Santiago` |

Hijri and Hebrew days start the evening before: their `start` is 18:00 of the previous day and `end` is 18:00 of the day itself. Hijri dates follow the Umm al-Qura calendar and are known for 1970 to 2076, Hebrew dates for 1969 to 2099, the lunisolar and equinox tables cover 1900 to 2100. Outside those ranges the holiday is left out and a warning is logged once.

## Moving the date

| Rule | Meaning |
|------|---------|
| `3rd monday in January` | The nth weekday of a month. `in` means on or after the 1st. |
| `monday after 06-01` | The first Monday on or after June 1st. `2nd monday after 06-01` is the one after that. |
| `friday before 11-01` | The last Friday strictly before November 1st |
| `friday after 4th thursday in November` | Clauses chain: the Friday after Thanksgiving |
| `12-25 if sunday then next monday` | Moves the date when it falls on the listed weekdays. `next monday` from a Monday moves a full week. |
| `12-25 and if sunday then next monday` | Keeps December 25th and adds the Monday as a substitute day |
| `substitutes 12-25 if saturday then previous friday` | Only produces the substitute day, and only when the condition holds |
| `01-01 and if saturday then next monday if sunday then next tuesday` | Several conditions; the first one that matches wins |
| `12-31 14:00 if sunday then 00:00` | A condition can change the start time instead |
| `09-22 if 09-21 and 09-23 is public holiday` | A bridge day, only when the other dates are holidays of that type |
| `03-23 if is public holiday then next monday` | Moves the date when another holiday of that type falls on it |

## Filtering the years

| Rule | Meaning |
|------|---------|
| `01-01 not on sunday` / `01-02 on monday` | Only when the date falls on (or not on) the weekdays |
| `1st sunday in October in even years` | Also `odd`, `leap` and `non-leap` years |
| `12-01 every 6 years since 1934` | Every nth year counting from a year |
| `02-22 since 2022` | From that year on, `since 2022-09-09` for a day |
| `julian 12-25 prior to 2023` | Before that year, `since 2020 prior to 2050` for a range |

## Times and durations

`12-24 14:00` starts at 14:00 and still ends at midnight. `easter -46 PT14H` lasts 14 hours, `1 Shawwal P3D` three days. Durations follow ISO 8601 with days, hours and minutes.

## Rule attributes

Beyond the string, the data can attach attributes to a rule, visible in `Dayoff.rules/2`:

- `name`, a map by language or a single string, and `_name` for one of the shared names.
- `type`: `public`, `bank`, `school`, `optional` or `observance`, public when absent.
- `substitute: true` lets a moved date be reported as a substitute day, with the localized "(substitute day)" suffix.
- `active`: a list of `from` and `to` dates the rule applies in, overriding `since` and `prior to`.
- `disable` and `enable`: single dates the government moved a holiday to, or cancelled. `disable: ["2015-11-23"], enable: ["2015-11-27"]` moves that year's occurrence.
- `note`: free text.

A state or region repeats a country rule string with `false` to remove it, or with new attributes to change it.

## Differences from the reference implementation

Every date dayoff produces is checked against date-holidays, so the two agree, with three exceptions where dayoff deliberately differs:

- Times are wall-clock in the country's default zone and are never converted through a timezone database. date-holidays converts them to instants and back, which shifts a midnight that doesn't exist on a daylight saving day.
- State and region codes are matched as they are. date-holidays uppercases them before looking them up, so a code like the Cook Islands' `Aitutaki` never resolves there and quietly returns the national holidays.
- Zones, languages and the day off declared on a region are found. date-holidays never reaches the region level for those because of a typo.
