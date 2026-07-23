module Plans
  module SRP
    class ElectricVehicle < Base
      include ::SRP::Dates

      def notes
        "Only available to customers with a plug-in battery or hybrid vehicle."
      end

      def plan_code
        "E-29"
      end

      def plan_label
        "Electric Vehicle"
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
        super_offpeak_level date
      end

      def rate(date)
        l = level date
        case season(date)
        when :winter
          case l
          when :super_off_peak then 0.0792
          when :off_peak then 0.0963
          when :on_peak then 0.1097
          else raise "Bad level"
          end
        when :summer
          case l
          when :super_off_peak then 0.0793
          when :off_peak then 0.0964
          when :on_peak then 0.2195
          else raise "Bad level"
          end
        when :summer_peak
          case l
          when :super_off_peak then 0.0794
          when :off_peak then 0.0965
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
