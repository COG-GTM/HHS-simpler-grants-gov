import SGModels

#if DEBUG
public enum SampleFormResponseFactory {
    public static func minimalRequiredResponse(for form: FormDefinition) -> JSONValue {
        var response = RequiredFieldValidator.minimalInstance(schema: form.formJsonSchema)
        guard form.formId == "1623b310-85be-496a-b84b-34bdee22a68a",
              case var .object(values) = response else {
            return response
        }

        values.removeValue(forKey: "total_estimated_funding")
        values.removeValue(forKey: "applicant_type_other_specify")
        values["applicant_type_code"] = .array([.string("E: Regional Organization")])
        values["employer_taxpayer_identification_number"] = .string("123456789")
        values["project_start_date"] = .string("2027-01-01")
        values["project_end_date"] = .string("2027-12-31")
        values["authorized_representative_email"] = .string("dana@bluefieldchc.org")
        values["federal_estimated_funding"] = .string("540000")
        values["applicant_estimated_funding"] = .string("0")
        values["state_estimated_funding"] = .string("0")
        values["local_estimated_funding"] = .string("0")
        values["other_estimated_funding"] = .string("0")
        values["program_income_estimated_funding"] = .string("0")
        response = .object(values)
        return response
    }
}
#endif
