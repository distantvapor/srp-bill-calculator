module SRP
  module Dates
    def season(date)
      return :winter if winter?(date)
      return :summer_peak if summer_peak?(date)
      return :summer if summer?(date)
      raise "Bad date!"
    end

    def winter?(date)
      (11..12).cover?(date.month) ||
      (1..4).cover?(date.month)
    end

    def summer?(date)
      (5..6).cover?(date.month) ||
      (9..10).cover?(date.month)
    end

    def summer_peak?(date)
      (7..8).cover?(date.month)
    end

    def weekend?(date)
      date.wday == 0 || date.wday == 6
    end

    def holiday?(date)
      return true if new_years_day?(date)
      return true if observed_new_years_day?(date)
      return true if independence_day?(date)
      return true if observed_independence_day?(date)
      return true if christmas_day?(date)
      return true if observed_christmas_day?(date)
      return true if memorial_day?(date)
      return true if labor_day?(date)
      return true if thanksgiving?(date)
      false
    end

    def new_years_day?(date)
      date.month == 1 && date.day == 1
    end

    def observed_new_years_day?(date)
      date.month == 12 && date.day == 31 && date.wday == 5 ||
        date.month == 1 && date.day == 2 && date.wday == 1
    end

    def independence_day?(date)
      date.month == 7 && date.day == 4
    end

    def observed_independence_day?(date)
      date.month == 7 && date.day == 3 && date.wday == 5 ||
        date.month == 7 && date.day == 5 && date.wday == 1
    end

    def christmas_day?(date)
      date.month == 12 && date.day == 25
    end

    def observed_christmas_day?(date)
      date.month == 12 && date.day == 24 && date.wday == 5 ||
        date.month == 12 && date.day == 26 && date.wday == 1
    end

    def memorial_day?(date)
      date.month == 5 && date.wday == 1 && (25..31).cover?(date.day)
    end

    def labor_day?(date)
      date.month == 9 && date.wday == 1 && (1..7).cover?(date.day)
    end

    def thanksgiving?(date)
      date.month == 11 && date.wday == 4 && (22..28).cover?(date.day)
    end

    def standard_level(date)
      return :off_peak if holiday?(date)
      case date.wday
      when 0, 6
        :off_peak
      else
        case season(date)
        when :winter
          case date.hour
          when 5...9, 17...21
            :on_peak
          else
            :off_peak
          end
        else
          case date.hour
          when 14...20
            :on_peak
          else
            :off_peak
          end
        end
      end
    end

    def super_offpeak_level(date)
      # Super off-peak (11pm-5am) applies year-round including holidays and weekends
      return :super_off_peak if (0...5).cover?(date.hour) || date.hour == 23

      # On-peak does NOT apply on holidays
      return :off_peak if holiday?(date)

      case season(date)
      when :winter
        case date.hour
        when 5...9, 17...21
          weekend?(date) ? :off_peak : :on_peak
        else
          :off_peak
        end
      else
        case date.hour
        when 14...20
          weekend?(date) ? :off_peak : :on_peak
        else
          :off_peak
        end
      end
    end
  end
end
