module Plans
  module SRP
    class ResidentialDemand < Base
      include ::SRP::Dates

      def plan_code
        "E-27P"
      end

      def plan_label
        "ResidentialDemand"
      end

      def discontinued?
        true
      end

      def notes
        "Demand billed on the maximum on-peak 30-minute kW demand."
      end

      def fixed_charges
        case (@options && @options[:manage_demand_tier]) || 1
        when 1 then 20.0
        when 2 then 30.0
        when 3 then 40.0
        else 20.0
        end
      end

      def level(date)
        return :off_peak if holiday?(date)
        return :off_peak if weekend?(date)

        case season(date)
        when :winter
          (5...9).cover?(date.hour) || (17...21).cover?(date.hour) ? :on_peak : :off_peak
        else
          (14...20).cover?(date.hour) ? :on_peak : :off_peak
        end
      end

      def rate(date)
        l = level(date)

        case season(date)
        when :winter
          case l
          when :off_peak then 0.0634
          when :on_peak then 0.0673
          else raise "Bad level"
          end
        when :summer
          case l
          when :off_peak then 0.0560
          when :on_peak then 0.0662
          else raise "Bad level"
          end
        when :summer_peak
          case l
          when :off_peak then 0.0613
          when :on_peak then 0.0823
          else raise "Bad level"
          end
        else
          raise "Bad level"
        end
      end

      def demand_usage(date, kwh)
        return 0 unless level(date) == :on_peak
        kwh
      end

      def demand_for_period(date)
        key = date.strftime("%Y-%m")
        demand = demand_by_month[key] || []
        return 0 if demand.empty?
        demand.compact.max || 0
      end

      def demand_cost(demand, date)
        remaining = demand
        total = 0.0

        demand_blocks_for(date).each do |limit, rate|
          break if remaining <= 0
          chunk = [remaining, limit].min
          total += chunk * rate
          remaining -= chunk
        end

        total
      end

      def demand_blocks_for(date)
        case season(date)
        when :summer
          [[3.0, 9.77], [7.0, 16.24], [Float::INFINITY, 29.18]]
        when :summer_peak
          [[3.0, 11.90], [7.0, 19.97], [Float::INFINITY, 36.05]]
        when :winter
          [[3.0, 4.93], [7.0, 7.02], [Float::INFINITY, 11.00]]
        else
          raise "Bad season"
        end
      end
    end
  end
end
