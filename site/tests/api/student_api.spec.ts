import {  getCurrentSemester, postRequest, getRequest } from './utils';
import { describe, expect, it } from '@jest/globals';

const valuesUrl = `/api/${getCurrentSemester(false)}/sample/gradeable/subdirectory_vcs_homework/values`
describe('Tests cases for the Student API', () => {
    it('Should get correct responses', async () => {
        await postRequest('/api/token', {'user_id': 'instructor', 'password': 'instructor'}).then(async response => {
            const key = response['data']['token'];
            console.log(key);
            const valuesResponse = await getRequest(valuesUrl + '?user_id=student', key);
            console.log(valuesResponse);
            expect(valuesResponse).toHaveProperty('status', 'success');
            // Can't test exact values due to randomness of CI speed
            const data = valuesResponse['data'];
            expect(data).toHaveProperty('is_queued');
            expect(data).toHaveProperty('queue_position'),
            expect(data).toHaveProperty('is_grading'),
            expect(data).toHaveProperty('has_submission'),
            expect(data).toHaveProperty('autograding_complete'),
            expect(data).toHaveProperty('has_active_version'),
            expect(data).toHaveProperty('highest_version'),
            expect(data).toHaveProperty('total_points'),
            expect(data).toHaveProperty('total_percent');
            // console.log(data.test_cases[0]);
            const python_test = {
                'name': 'Python test',
                'details': 'python3 *.py',
                'has_extra_results': true,
                'is_extra_credit': false,
                'points_available': 5,
                'points_received': 5,
                'testcase_message': '',
            };
            const submitted_pdf = {
                'name': 'Submitted a .pdf file',
                'details': '',
                'has_extra_results': true,
                'is_extra_credit': false,
                'points_available': 1,
                'points_received': 1,
                'testcase_message': '',
            };
            const words = {
                'name': 'Required 500-1000 Words',
                'details': '',
                'has_extra_results': true,
                'is_extra_credit': false,
                'points_available': 1,
                'points_received': 0,
                'testcase_message': '',
            };
            expect(data.test_cases[0]).toEqual(python_test);
            expect(data.test_cases[1]).toEqual(submitted_pdf);
            expect(data.test_cases[2]).toEqual(words);
        });
        

        // const not_student_response = await getRequest(valuesUrl + '?user_id=not_a_student',key);
        //     expect(not_student_response).toHaveProperty('status', 'success');
        //     expect(not_student_response.body.message).toEqual('Graded gradesdsable for user with id not_a_student does not exist');
        });

    //     getApiKey('student', 'student').then((key) => {
    //         // Success
    //         cy.request({
    //             method: 'GET',
    //             url: `${Cypress.config('baseUrl')}/api/${getCurrentSemester()}/sample/gradeable/subdirectory_vcs_homework/values?user_id=student`,
    //             headers: {
    //                 Authorization: key,
    //             }, body: {
    //             },
    //         }).then((response) => {
    //             expect(response.body.status).to.equal('success');
    //             // Can't test exact values due to randomness of CI speed
    //             const data = response.body.data;
    //             const data_string = JSON.stringify(response.body.data);
    //             expect(data_string).toHaveProperty('is_queued');
    //             expect(data_string).toHaveProperty('queue_position'),
    //             expect(data_string).toHaveProperty('is_grading'),
    //             expect(data_string).toHaveProperty('has_submission'),
    //             expect(data_string).toHaveProperty('autograding_complete'),
    //             expect(data_string).toHaveProperty('has_active_version'),
    //             expect(data_string).toHaveProperty('highest_version'),
    //             expect(data_string).toHaveProperty('total_points'),
    //             expect(data_string).toHaveProperty('total_percent');
    //             expect(data_string).toHaveProperty('test_cases');
    //             // CI doesn't have grades
    //             // Requires VCS Subdirectory gradeable to be graded
    //             if (Cypress.env('run_area') !== 'CI') {
    //                 
    //             }
    //         });

    //         // Success, successfully sent to be graded
    //         cy.request({
    //             method: 'POST',
    //             url: `${Cypress.config('baseUrl')}/api/${getCurrentSemester()}/sample/gradeable/subdirectory_vcs_homework/grade`,
    //             headers: {
    //                 Authorization: key,
    //             }, body: {
    //                 'user_id': 'student',
    //                 'vcs_checkout': 'true',
    //                 'git_repo_id': 'none',
    //             },
    //         }).then((response) => {
    //             expect(response.body.status).to.equal('success');
    //             expect(response.body.data).toHaveProperty('Successfully uploaded version').and.toHaveProperty('for Subdirectory VCS Homework');
    //         });
    //         // Fail
    //         cy.request({
    //             method: 'POST',
    //             url: `${Cypress.config('baseUrl')}/api/${getCurrentSemester()}/sample/gradeable/subdirectory_vcs_homework/values`,
    //             headers: {
    //                 Authorization: key,
    //             }, body:{},
    //         }).then((response) => {
    //             expect(response.body.status).to.equal('fail');
    //             expect(response.body.message).to.equal('Method not allowed.');
    //         });

    //         // Fail, invalid API key
    //         cy.request({
    //             method: 'GET',
    //             url: `${Cypress.config('baseUrl')}/api/${getCurrentSemester()}/sample/gradeable/subdirectory_vcs_homework/values`,
    //             headers: {
    //                 Authorization: 'key',
    //             }, body:{},
    //         }).then((response) => {
    //             expect(response.body.status).to.equal('fail');
    //             expect(response.body.message).to.equal('Unauthenticated access. Please log in.');
    //         });
    //         // Fail, API key not for given user_id
    //         cy.request({
    //             method: 'GET',
    //             url: `${Cypress.config('baseUrl')}/api/${getCurrentSemester()}/sample/gradeable/subdirectory_vcs_homework/values?user_id=not_a_student`,
    //             headers: {
    //                 Authorization: key,
    //             }, body:{
    //             },
    //         }).then((response) => {
    //             expect(response.body.status).to.equal('fail');
    //             expect(response.body.message).to.equal('API key and specified user_id are not for the same user.');
    //         });
    //         // Fail, endpoint not found.
    //         cy.request({
    //             method: 'GET',
    //             url: `${Cypress.config('baseUrl')}/api/not/found/url`,
    //             headers: {
    //                 Authorization: key,
    //             }, body:{},
    //         }).then((response) => {
    //             expect(response.body.status).to.equal('fail');
    //             expect(response.body.message).to.equal('Endpoint not found.');
    //         });

    //         // Specific fails for values API
    //         // Gradeable doesn't exist
    //         cy.request({
    //             method: 'GET',
    //             url: `${Cypress.config('baseUrl')}/api/${getCurrentSemester()}/sample/gradeable/not_found_gradeable/values?user_id=student`,
    //             headers: {
    //                 Authorization: key,
    //             }, body: {
    //             },
    //         }).then((response) => {
    //             expect(response.body.status).to.equal('fail');
    //             expect(response.body.message).to.equal('Gradeable does not exist');
    //         });
    //     });
    // });
});
