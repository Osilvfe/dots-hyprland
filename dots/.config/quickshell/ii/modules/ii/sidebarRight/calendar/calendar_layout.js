// SPDX-License-Identifier: GPL-3.0-or-later
// Lunar calendar functions

const weekDays = [ // MONDAY IS THE FIRST DAY OF THE WEEK
    { day: 'Mo', today: 0 },
    { day: 'Tu', today: 0 },
    { day: 'We', today: 0 },
    { day: 'Th', today: 0 },
    { day: 'Fr', today: 0 },
    { day: 'Sa', today: 0 },
    { day: 'Su', today: 0 },
]

// Lunar calendar data 1900-2100
// Each entry encodes one lunar year (classic lunarInfo layout):
// Bits 0-3:    leap month (0-12, 0=no leap)
// Bits 4-15:   month length flags (bit15=month 1, bit4=month 12; 1=30d, 0=29d)
// Bit 16:      leap month length (1=30d, 0=29d)
// The Chinese New Year offset is computed iteratively from base 1900-01-31
const lunarInfo = [
    0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,
    0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,
    0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,
    0x06566, 0x0d4a0, 0x0ea50, 0x16a95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
    0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,
    0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0,
    0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,
    0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6,
    0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
    0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x05ac0, 0x0ab60, 0x096d5, 0x092e0,
    0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,
    0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
    0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
    0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45,
    0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
    0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06aa0, 0x1a6c4, 0x0aae0,
    0x092e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4,
    0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0,
    0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160,
    0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a4d0, 0x0d150, 0x0f252,
    0x0d520
]

// Lunar month names
const lunarMonthNames = [
    "", "正月", "二月", "三月", "四月", "五月", "六月",
    "七月", "八月", "九月", "十月", "冬月", "腊月"
]

// Lunar day names
const lunarDayNames = [
    "", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
    "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
]

function leapMonth(y) {
    return lunarInfo[y - 1900] & 0xf
}

function leapDays(y) {
    if (leapMonth(y)) {
        return (lunarInfo[y - 1900] & 0x10000) ? 30 : 29
    }
    return 0
}

function monthDays(y, m) {
    return (lunarInfo[y - 1900] & (0x10000 >> m)) ? 30 : 29
}

function lunarYearDays(y) {
    let sum = 0
    for (let i = 1; i <= 12; i++) sum += monthDays(y, i)
    return sum + leapDays(y)
}

// Days from 1900-01-01 to solar date (year, month 1-12, day)
function solarDayOffset(y, m, d) {
    let offset = 0
    for (let i = 1900; i < y; i++) {
        offset += ((i % 400 === 0 || (i % 4 === 0 && i % 100 !== 0)) ? 366 : 365)
    }
    const monthDaysArray = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    const isLeap = (y % 400 === 0 || (y % 4 === 0 && y % 100 !== 0))
    for (let i = 1; i < m; i++) {
        offset += monthDaysArray[i]
        if (i === 2 && isLeap) offset++
    }
    offset += d - 1
    return offset
}

// Convert solar date to lunar date
// Returns { year, month, day, isLeap } or null if out of range
function solarToLunar(y, m, d) {
    // Base: 1900-01-31 is lunar 1900-01-01
    const baseSolarOffset = 30 // Jan 31 is 30 days from Jan 1
    let solarOffset = solarDayOffset(y, m, d) - solarDayOffset(1900, 1, 1)

    if (solarOffset < baseSolarOffset) return null // Before 1900

    let ly = 1900
    let lunarOffset = baseSolarOffset // Days from 1900-01-01 to lunar new year

    // Find which lunar year the solar date falls in
    // Move forward year by year
    while (ly <= 2100) {
        const yearDays = lunarYearDays(ly)
        if (solarOffset < lunarOffset + yearDays) break
        lunarOffset += yearDays
        ly++
    }

    if (ly > 2100) return null

    // Now find the month within this lunar year
    const dayOfYear = solarOffset - lunarOffset // 0 = first day of lunar year

    let lm = 1
    let ld = dayOfYear
    let isLeap = false

    for (lm = 1; lm <= 12; lm++) {
        const md = monthDays(ly, lm)
        if (ld < md) break
        ld -= md

        // Check leap month after this month
        if (lm === leapMonth(ly)) {
            const lmd = leapDays(ly)
            if (ld < lmd) {
                isLeap = true
                break
            }
            ld -= lmd
        }
    }

    return {
        year: ly,
        month: lm > 12 ? 12 : lm,
        day: ld + 1,
        isLeap: isLeap
    }
}

// Get display text for lunar date
// Returns short text suitable for calendar cells
function getLunarText(solarYear, solarMonth, solarDay) {
    const lunar = solarToLunar(solarYear, solarMonth, solarDay)
    if (!lunar) return ""

    const prefix = lunar.isLeap ? "闰" : ""

    // Show month name for 初一 (first day of month)
    if (lunar.day === 1) {
        return prefix + lunarMonthNames[lunar.month]
    }

    return lunarDayNames[lunar.day]
}

// Solar calendar helpers
function checkLeapYear(year) {
    return (
        year % 400 == 0 ||
        (year % 4 == 0 && year % 100 != 0));
}

function getMonthDays(month, year) {
    const leapYear = checkLeapYear(year);
    if ((month <= 7 && month % 2 == 1) || (month >= 8 && month % 2 == 0)) return 31;
    if (month == 2 && leapYear) return 29;
    if (month == 2 && !leapYear) return 28;
    return 30;
}

function getNextMonthDays(month, year) {
    const leapYear = checkLeapYear(year);
    if (month == 1 && leapYear) return 29;
    if (month == 1 && !leapYear) return 28;
    if (month == 12) return 31;
    if ((month <= 7 && month % 2 == 1) || (month >= 8 && month % 2 == 0)) return 30;
    return 31;
}

function getPrevMonthDays(month, year) {
    const leapYear = checkLeapYear(year);
    if (month == 3 && leapYear) return 29;
    if (month == 3 && !leapYear) return 28;
    if (month == 1) return 31;
    if ((month <= 7 && month % 2 == 1) || (month >= 8 && month % 2 == 0)) return 30;
    return 31;
}

function getDateInXMonthsTime(x) {
    var currentDate = new Date(); // Get the current date
    if (x == 0) return currentDate; // If x is 0, return the current date

    var targetMonth = currentDate.getMonth() + x; // Calculate the target month
    var targetYear = currentDate.getFullYear(); // Get the current year

    // Adjust the year and month if necessary
    targetYear += Math.floor(targetMonth / 12);
    targetMonth = (targetMonth % 12 + 12) % 12;

    // Create a new date object with the target year and month
    var targetDate = new Date(targetYear, targetMonth, 1);

    // Set the day to the last day of the month to get the desired date
    // targetDate.setDate(0);

    return targetDate;
}

function getCalendarLayout(dateObject, highlight, holidayData) {
    if (!dateObject) dateObject = new Date();
    const weekday = (dateObject.getDay() + 6) % 7; // MONDAY IS THE FIRST DAY OF THE WEEK
    const day = dateObject.getDate();
    const month = dateObject.getMonth() + 1;
    const year = dateObject.getFullYear();
    const weekdayOfMonthFirst = (weekday + 35 - (day - 1)) % 7;
    const daysInMonth = getMonthDays(month, year);
    const daysInNextMonth = getNextMonthDays(month, year);
    const daysInPrevMonth = getPrevMonthDays(month, year);

    // Fill
    var monthDiff = (weekdayOfMonthFirst == 0 ? 0 : -1);
    var toFill, dim;
    if (weekdayOfMonthFirst == 0) {
        toFill = 1;
        dim = daysInMonth;
    }
    else {
        toFill = (daysInPrevMonth - (weekdayOfMonthFirst - 1));
        dim = daysInPrevMonth;
    }
    var calendar = [...Array(6)].map(() => Array(7));
    var i = 0, j = 0;
    while (i < 6 && j < 7) {
        // Calculate solar date for this cell to get lunar info
        var cellYear = year, cellMonth = month + monthDiff, cellDay = toFill;
        if (cellMonth < 1) { cellMonth = 12; cellYear--; }
        if (cellMonth > 12) { cellMonth = 1; cellYear++; }

        var holiday = null;
        var isOffDay = null;
        if (holidayData) {
            var hKey = cellYear + "-" + String(cellMonth).padStart(2, "0") + "-" + String(cellDay).padStart(2, "0");
            holiday = holidayData[hKey] || null;
        }

        // Nager.Date gives the exact festival day; other off days just get a badge
        var showHolidayName = holiday && holiday.name !== "";
        var offBadge = holiday && (holiday.isOffDay || showHolidayName);
        var workBadge = holiday && !showHolidayName && holiday.isOffDay === false;

        calendar[i][j] = {
            "day": toFill,
            "today": ((toFill == day && monthDiff == 0 && highlight) ? 1 : (
                monthDiff == 0 ? 0 : -1
            )),
            "lunar": getLunarText(cellYear, cellMonth, cellDay),
            "holiday": showHolidayName ? holiday.name : "",
            "holidayOff": offBadge ? "休" : "",
            "workday": workBadge ? "班" : ""
        };
        // Increment
        toFill++;
        if (toFill > dim) { // Next month?
            monthDiff++;
            if (monthDiff == 0)
                dim = daysInMonth;
            else if (monthDiff == 1)
                dim = daysInNextMonth;
            toFill = 1;
        }
        // Next tile
        j++;
        if (j == 7) {
            j = 0;
            i++;
        }

    }
    return calendar;
}
