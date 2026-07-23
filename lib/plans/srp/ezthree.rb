module Plans
  module SRP
    class EZThree < Base
      include ::SRP::Dates

      def plan_code
        "E-22"
      end

      def plan_label
        "EZThree"
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

        start_hour = (@options && @options[:srp_ez3_start_hour]) || 16
        (start_hour...(start_hour + 3)).cover?(date.hour) ? :on_peak : :off_peak
      end

      def rate(date)
        l = level(date)

        case season(date)
        when :winter
          case l
          when :off_peak then 0.0964
          when :on_peak then 0.1287
          else raise "Bad level"
          end
        when :summer
          case l
          when :off_peak then 0.1022
          when :on_peak then 0.3087
          else raise "Bad level"
          end
        when :summer_peak
          case l
          when :off_peak then 0.1060
          when :on_peak then 0.3652
          else raise "Bad level"
          end
        else
          raise "Bad level"
        end
      end
    end
  end
end
