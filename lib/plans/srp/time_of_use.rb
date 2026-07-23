module Plans
  module SRP
    class TimeOfUse < Base
      include ::SRP::Dates

      def plan_code
        "E-26"
      end

      def plan_label
        "TimeOfUse"
      end

      def self.discontinued?
        true
      end

      def discontinued?
        true
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
        return :off_peak if holiday?(date)
        return :off_peak if weekend?(date)

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

      def rate(date)
        l = level date
        case season(date)
        when :winter
          case l
          when :off_peak then 0.0891
          when :on_peak then 0.1209
          else raise "Bad level"
          end
        when :summer
          case l
          when :off_peak then 0.0903
          when :on_peak then 0.2289
          else raise "Bad level"
          end
        when :summer_peak
          case l
          when :off_peak then 0.0926
          when :on_peak then 0.2604
          else raise "Bad level"
          end
        else
          raise "Bad level"
        end
      end
    end
  end
end
