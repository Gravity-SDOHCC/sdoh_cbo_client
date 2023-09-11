module ModelHelper
  extend ActiveSupport::Concern

  def remove_client_instances(resource)
    resource.client = nil
    @fhir_resource.each_element { |element| element.client = nil if element.respond_to? :client }
  end
end
