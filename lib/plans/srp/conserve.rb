module Plans
  module SRP
    class Conserve < Base
      include ::SRP::Dates

      def plan_code
        "E-28"
      end

      def plan_label
        "Conserve"
      end

      def fixed_charges
        case (@options && @options[:conserve_tier]) || 1
        when 1 then 20.0
        when 2 then 30.0
        when 3 then 40.0
        else 20.0
        end
      end

      def level(date)
        return :super_off_peak if (8...15).cover?(date.hour)
        return :on_peak if date.wday.between?(1, 5) && (18...21).cover?(date.hour)

        :off_peak
      end

      def rate(date)
        l = level date
        case season(date)
        when :summer
          case l
          when :off_peak then 0.1468
          when :super_off_peak then 0.0357
          when :on_peak then 0.1847
          else raise "Bad level"
          end
        when :summer_peak
          case l
          when :off_peak then 0.1238
          when :super_off_peak then 0.0623
          when :on_peak then 0.3982
          else raise "Bad level"
          end
        when :winter
          case l
          when :off_peak then 0.1355
          when :super_off_peak then 0.0432
          when :on_peak then 0.1508
          else raise "Bad level"
          end
        else
          raise "Bad level"
        end
      end
    end
  end
end
