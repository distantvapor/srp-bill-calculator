module Plans
  module SRP
    class Basic < Base
      include ::SRP::Dates

      def plan_code
        "E-23"
      end

      def plan_label
        "Basic"
      end

      def fixed_charges
        case (@options && @options[:basic_tier]) || 1
        when 1 then 20.0
        when 2 then 30.0
        when 3 then 40.0
        else 20.0
        end
      end

      def rate(date)
        case season(date)
        when :winter
          0.1097
        when :summer
          0.1204
        when :summer_peak
          0.1398
        else
          raise "Bad level"
        end
      end
    end
  end
end
