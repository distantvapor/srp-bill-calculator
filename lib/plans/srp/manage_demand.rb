module Plans
  module SRP
    class ManageDemand < Base
      include AverageDemandConcern
      include ::SRP::Dates

      def plan_code
        "E-16"
      end

      def plan_label
        "ManageDemand"
      end

      def fixed_charges
        case (@options && @options[:tier]) || 1
        when 1 then 20.0
        when 2 then 30.0
        when 3 then 40.0
        else 20.0
        end
      end

      def level(date)
        # Super off-peak (8am-3pm) applies year-round: weekdays, weekends, and holidays
        return :super_off_peak if (8...15).cover?(date.hour)

        # On-peak (5pm-10pm) is weekdays only, excluding holidays
        return :off_peak if holiday?(date) || weekend?(date)

        case date.hour
        when 17...22
          :on_peak
        else
          :off_peak
        end
      end

      def rate(date)
        l = level date
        case season(date)
        when :summer
          case l
          when :off_peak then 0.0957
          when :super_off_peak then 0.0355
          when :on_peak then 0.1219
          else raise "Bad level"
          end
        when :summer_peak
          case l
          when :off_peak then 0.0958
          when :super_off_peak then 0.0584
          when :on_peak then 0.1616
          else raise "Bad level"
          end
        when :winter
          case l
          when :off_peak then 0.0994
          when :super_off_peak then 0.0438
          when :on_peak then 0.1119
          else raise "Bad level"
          end
        else
          raise "Bad level"
        end
      end

      # Demand is the average of the daily maximum 60-minute kW readings during on-peak hours.
      def add_demand(date, kwh)
        return 0 unless level(date) == :on_peak
        super
      end

      def demand_usage(date, kwh)
        return 0 unless level(date) == :on_peak
        kwh
      end

      def demand_rate(date)
        if @options && @options[:manage_demand_dollar_per_kw]
          @options[:manage_demand_dollar_per_kw].to_f
        else
          case season(date)
          when :summer then 13.56
          when :summer_peak then 17.78
          when :winter then 9.61
          else raise "Bad level"
          end
        end
      end
    end
  end
end
