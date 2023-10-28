# Gravity SDOH CBO Client Reference Implementation

This is a reference implementation for the Communinity Base Organization (CBO)
system as defined in the [Gravity SDOHCC Implementation
Guide](http://hl7.org/fhir/us/sdoh-clinicalcare/).

This CBO RI behaves as a [‘Light’ referral
recipient](http://hl7.org/fhir/us/sdoh-clinicalcare/CapabilityStatement-SDOHCC-ReferralRecipientLight.html).
It acts as client, querying for tasks on the initiating Referral Sources or
Coordination Platforms and creating any resulting Procedure records within the
server they received the request from.

## Setup
This application is built with Ruby on Rails. To run it locally, first [install
rails](https://guides.rubyonrails.org/getting_started.html#creating-a-new-rails-project-installing-rails).

* Clone this repository: `git clone
  https://github.com/Gravity-SDOHCC/sdoh_cbo_client.git`
* Navigate to the root of this repository: `cd sdoh_cbo_client`
* Install dependencios: `bundle install`
* Set up the database: `bundle exec rake db:setup`
* Run the application: `bundle exec rails s`
  * If you need to run the application on a different port, specify the `PORT`
    environment variable: `PORT=3333 bundle exec rails s`
* Navigate to `http://localhost:3000` in your browser

## Usage
See [the usage
documentation](https://github.com/Gravity-SDOHCC/sdoh_referral_source_client/blob/master/docs/usage.md)
for instructions on using the reference implementations.

## Known Issues
* Sometimes it takes multiple attempts to connect to a FHIR server
* Sometimes when new links are added to the page (such as when a new referral is
  received), clicking o the link will have no effect until the page is reloaded
* Users can not select which procedure is being performed in order to complete a
  referral

## License
Copyright 2023 The MITRE Corporation

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at
```
http://www.apache.org/licenses/LICENSE-2.0
```
Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.

## Trademark Notice

HL7, FHIR and the FHIR [FLAME DESIGN] are the registered trademarks of Health
Level Seven International and their use does not constitute endorsement by HL7.


## Questions and Contributions
Questions about the project can be asked in the [Gravity SDOH stream on the FHIR Zulip Chat](https://chat.fhir.org/#narrow/stream/233957-Gravity-sdoh-cc).

This project welcomes Pull Requests. Any issues identified with the RI should be submitted via the [GitHub issue tracker](https://github.com/Gravity-SDOHCC/sdoh_cbo_client/issues).

As of October 1, 2023, The Lantana Consulting Group is responsible for the management and maintenance of this Reference Implementation.
In addition to posting on FHIR Zulip Chat channel mentioned above you can contact [Corey Spears](mailto:corey.spears@lantanagroup.com) for questions or requests.
