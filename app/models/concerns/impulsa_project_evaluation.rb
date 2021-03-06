module ImpulsaProjectEvaluation
  extend ActiveSupport::Concern
  
  class EvaluatorAccessor
    def initialize project
      @project = project
    end

    def [](index)
      @project.send("evaluator#{index}") if index.is_a?(Fixnum) && index>0 && index<=ImpulsaProjectEvaluation::EVALUATORS
    end

    def []=(index, value)
      raise "Can't set same user as different evaluators for project." if value.present? && @project.evaluators.any? {|i| i!=index && self[i]==value}
      @project.send("evaluator#{index}=", value) if index.is_a?(Fixnum) && index>0 && index<=ImpulsaProjectEvaluation::EVALUATORS
    end
  end

  included do
    include ActiveModel::Validations::SpanishVatValidatorsHelpers
    include ActiveModel::Validations::EmailValidatorHelpers

    EVALUATORS = 2

    def evaluators
      1..EVALUATORS
    end 

    (1..EVALUATORS).each do |i|
      belongs_to :"evaluator#{i}", class_name: "User"
      store :"evaluator#{i}_evaluation", coder: YAML 
    end

    def evaluation
      impulsa_edition_category.evaluation
    end

    def evaluator
      @evaluator ||= EvaluatorAccessor.new(self)
    end

    def current_evaluator user_id
      evaluators.each do |i|
        e = evaluator[i]
        return i if e.blank? || e.id==user_id
      end
      return nil
    end

    def evaluation_values evaluator
      send("evaluator#{evaluator}_evaluation")
    end

    def evaluation_admin_params
      _all = evaluation.map do |sname, step|
        step[:groups].map do |gname,group|
          group[:fields].map do |fname, field|
            evaluators.map do |i|
              "_evl#{i}_#{gname}__#{fname}"
            end
          end .flatten(1)
        end .flatten(1)
      end .flatten(1)
    end

    def evaluation_has_errors? options = {}
      evaluators.any? do |i|
        evaluation_count_errors(i, options) > 0
      end
    end      

    def evaluation_count_errors evaluator, options = {}
      evaluation.sum do |sname, step|
        evaluation_step_errors(evaluator, sname, options).count
      end
    end

    def evaluation_step_errors evaluator, step, options = {}
      evaluation[step][:groups].map do |gname,group|
        group[:fields].map do |fname, field|
          [ "_evl#{evaluator}_#{gname}__#{fname}", evaluation_field_error(evaluator, gname, fname, group, field, options) ]
        end.select(&:last)
      end.flatten(1)
    end
    def evaluation_field_error evaluator, gname, fname, group = nil, field = nil, options = {}
      group = evaluation.collect {|sname, step| step[:groups][gname] } .compact.first if group.nil?
      field = group[:fields][fname] if field.nil?
      value = evaluation_values(evaluator)["#{gname}.#{fname}"]
      return "no es un campo" if field.nil?
      return "es obligatorio" if value.blank? && !field[:optional]
      if value.present?
        return "debe ser aceptado" if value!="1" && field[:format]=="accept"
        return "puede tener hasta #{field[:limit]} caracteres" if field[:limit] && value.length>field[:limit]
        return "no es un NIF correcto" if field[:format]=="cif" && !validate_cif(value)
        return "no es un DNI correcto" if field[:format]=="dni" && !validate_nif(value)
        return "no es un NIE correcto" if field[:format]=="nie" && !validate_nie(value)
        return "no es un DNI o NIE correcto" if field[:format]=="dninie" && !(validate_nif(value) || validate_nie(value))
        return "no es un teléfono válido" if field[:format]=="phone" && Phonelib.parse(value).valid?
        return "no es una dirección web válida" if field[:type]=="url" && URI::regexp(%w(http https)).match(value).nil?
        error = validate_email(value) if field[:type]=="email"
        return error if error
      end
      nil
    end

    def assign_evaluation_value evaluator, gname, fname, value
      field = evaluation.map {|sname, step| step[:groups][gname] && step[:groups][gname][:fields][fname] } .compact.first
      if field
        old_value = evaluation_values(evaluator)["#{gname}.#{fname}"]
        evaluation_values(evaluator)["#{gname}.#{fname}"] = value
        return :ok
      end
      return :wrong_field
    end

    def evaluation_path evaluator, gname, fname
      files_folder + "#{evaluator}-" + evaluation_values(evaluator)["#{gname}.#{fname}"]
    end

    def evaluation_method_missing(method_sym, *arguments, &block)
      evaluators.each do |i|
        if method_sym.to_s =~ /^_evl#{i}_(.+)__([^=]+)=?$/
          self.instance_eval <<-RUBY
            def _evl#{i}_#{$1}__#{$2}
              evaluation_values(#{i})["#{$1}.#{$2}"]
            end
            def _evl#{i}_#{$1}__#{$2}= value
              assign_evaluation_value(#{i}, :"#{$1}", :"#{$2}", value)
            end
          RUBY
          return send(method_sym, *arguments)
        end
      end
      :super
    end

    def can_finish_evaluation? user
      self.validable? && !self.evaluation_has_errors? && user.admin?
    end
  end
end