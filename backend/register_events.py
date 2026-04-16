import boto3
import datetime
import ephem
import jpholiday
import exchange_calendars as xcals

dynamodb = boto3.resource('dynamodb', region_name='ap-northeast-1')
table = dynamodb.Table('market_events')

def register_year(year):
    """指定年のマーケットイベントをDynamoDBに登録"""
    for month in range(1, 13):
        first    = datetime.date(year, month, 1)
        last_day = datetime.date(year, month + 1, 1) - datetime.timedelta(days=1) \
                   if month < 12 else datetime.date(year, 12, 31)
        prefix   = f"{year}-{str(month).zfill(2)}"
        events   = []

        # 日本の祝日
        d = first
        while d <= last_day:
            if jpholiday.is_holiday(d):
                events.append({
                    "date":  str(d),
                    "label": f"🇯🇵 {jpholiday.is_holiday_name(d)}",
                    "type":  "holiday_jp",
                    "color": "pink",
                })
            d += datetime.timedelta(days=1)

        # 米国市場休場日
        try:
            xnys = xcals.get_calendar("XNYS")
            sessions = xnys.sessions_in_range(str(first), str(last_day))
            session_strs = {str(s.date()) for s in sessions}
            d = first
            while d <= last_day:
                if d.weekday() < 5 and str(d) not in session_strs:
                    events.append({
                        "date":  str(d),
                        "label": "🇺🇸 米国市場休場",
                        "type":  "holiday_us",
                        "color": "blueGrey",
                    })
                d += datetime.timedelta(days=1)
        except Exception as e:
            print(f"米国休場エラー: {e}")

        # 満月・新月
        try:
            d = first
            seen = set()
            while d <= last_day:
                dt = datetime.datetime(d.year, d.month, d.day)
                for fn, label, color, typ in [
                    (ephem.next_new_moon,  "🌑 新月", "grey",  "new_moon"),
                    (ephem.next_full_moon, "🌕 満月", "amber", "full_moon"),
                ]:
                    moon_date = ephem.Date(fn(dt)).datetime().date()
                    key = f"{moon_date}_{typ}"
                    if moon_date.month == month and key not in seen:
                        seen.add(key)
                        events.append({
                            "date":  str(moon_date),
                            "label": label,
                            "type":  typ,
                            "color": color,
                        })
                d += datetime.timedelta(days=1)
        except Exception as e:
            print(f"月齢エラー: {e}")

        # SQ（第2金曜）
        fri_count = 0
        d = first
        while d <= last_day:
            if d.weekday() == 4:
                fri_count += 1
                if fri_count == 2:
                    is_major = month in [3, 6, 9, 12]
                    events.append({
                        "date":  str(d),
                        "label": "メジャーSQ" if is_major else "SQ",
                        "type":  "major_sq" if is_major else "sq",
                        "color": "deepOrange" if is_major else "orange",
                    })
                    break
            d += datetime.timedelta(days=1)

        # 米雇用統計（第1金曜）
        d = first
        while d <= last_day:
            if d.weekday() == 4:
                events.append({
                    "date":  str(d),
                    "label": "🇺🇸 米雇用統計",
                    "type":  "jobs",
                    "color": "teal",
                })
                break
            d += datetime.timedelta(days=1)

        # 権利落ち日（月末から2営業日前）
        biz = 0
        d = last_day
        while biz < 2:
            if d.weekday() < 5:
                biz += 1
                if biz < 2:
                    d -= datetime.timedelta(days=1)
            else:
                d -= datetime.timedelta(days=1)
        events.append({
            "date":  str(d),
            "label": "権利落ち日（目安）",
            "type":  "rights",
            "color": "indigo",
        })

        # DynamoDBに保存
        for e in events:
            table.put_item(Item={
                "year_month": prefix,
                "date_type":  f"{e['date']}_{e['type']}",
                "date":       e["date"],
                "label":      e["label"],
                "type":       e["type"],
                "color":      e["color"],
            })
        print(f"{prefix}: {len(events)}件登録完了")

# FOMC（固定データ・年1回更新）
FOMC_DATES = [
    "2026-01-28","2026-03-18","2026-04-29","2026-06-17",
    "2026-07-29","2026-09-16","2026-10-28","2026-12-09",
]
BOJ_DATES = [
    "2026-01-23","2026-03-19","2026-04-28","2026-06-16",
    "2026-07-30","2026-09-17","2026-10-28","2026-12-18",
]

def register_fixed_events():
    for d in FOMC_DATES:
        ym = d[:7]
        table.put_item(Item={
            "year_month": ym,
            "date_type":  f"{d}_fomc",
            "date":       d,
            "label":      "FOMC 結果発表",
            "type":       "fomc",
            "color":      "purple",
        })
    for d in BOJ_DATES:
        ym = d[:7]
        table.put_item(Item={
            "year_month": ym,
            "date_type":  f"{d}_boj",
            "date":       d,
            "label":      "日銀 政策金利発表",
            "type":       "boj",
            "color":      "brown",
        })
    print("FOMC・日銀登録完了")

if __name__ == "__main__":
    register_year(2026)
    register_fixed_events()
    print("全登録完了！")