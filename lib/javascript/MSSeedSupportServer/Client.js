

function MSSeedSupportServer(url, auth, auth_cb) {

    var _url = url;
    var deprecationWarningSent = false;
    
    function deprecationWarning() {
        if (!deprecationWarningSent) {
            deprecationWarningSent = true;
            if (!window.console) return;
            console.log(
                "DEPRECATION WARNING: '*_async' method names will be removed",
                "in a future version. Please use the identical methods without",
                "the'_async' suffix.");
        }
    }

    var _auth = auth ? auth : { 'token' : '', 'user_id' : ''};
    var _auth_cb = auth_cb;


    this.getRastGenomeData = function (params, _callback, _errorCallback) {
    return json_call_ajax("MSSeedSupportServer.getRastGenomeData",
        [params], 1, _callback, _errorCallback);
};

    this.getRastGenomeData_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("MSSeedSupportServer.getRastGenomeData", [params], 1, _callback, _error_callback);
    };

    this.get_user_info = function (params, _callback, _errorCallback) {
    return json_call_ajax("MSSeedSupportServer.get_user_info",
        [params], 1, _callback, _errorCallback);
};

    this.get_user_info_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("MSSeedSupportServer.get_user_info", [params], 1, _callback, _error_callback);
    };

    this.authenticate = function (params, _callback, _errorCallback) {
    return json_call_ajax("MSSeedSupportServer.authenticate",
        [params], 1, _callback, _errorCallback);
};

    this.authenticate_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("MSSeedSupportServer.authenticate", [params], 1, _callback, _error_callback);
    };

    this.load_model_to_modelseed = function (params, _callback, _errorCallback) {
    return json_call_ajax("MSSeedSupportServer.load_model_to_modelseed",
        [params], 1, _callback, _errorCallback);
};

    this.load_model_to_modelseed_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("MSSeedSupportServer.load_model_to_modelseed", [params], 1, _callback, _error_callback);
    };

    this.create_plantseed_job = function (params, _callback, _errorCallback) {
    return json_call_ajax("MSSeedSupportServer.create_plantseed_job",
        [params], 1, _callback, _errorCallback);
};

    this.create_plantseed_job_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("MSSeedSupportServer.create_plantseed_job", [params], 1, _callback, _error_callback);
    };

    this.get_plantseed_genomes = function (params, _callback, _errorCallback) {
    return json_call_ajax("MSSeedSupportServer.get_plantseed_genomes",
        [params], 1, _callback, _errorCallback);
};

    this.get_plantseed_genomes_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("MSSeedSupportServer.get_plantseed_genomes", [params], 1, _callback, _error_callback);
    };

    this.kblogin = function (params, _callback, _errorCallback) {
    return json_call_ajax("MSSeedSupportServer.kblogin",
        [params], 1, _callback, _errorCallback);
};

    this.kblogin_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("MSSeedSupportServer.kblogin", [params], 1, _callback, _error_callback);
    };

    this.kblogin_from_token = function (params, _callback, _errorCallback) {
    return json_call_ajax("MSSeedSupportServer.kblogin_from_token",
        [params], 1, _callback, _errorCallback);
};

    this.kblogin_from_token_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("MSSeedSupportServer.kblogin_from_token", [params], 1, _callback, _error_callback);
    };
 

    /*
     * JSON call using jQuery method.
     */
    function json_call_ajax(method, params, numRets, callback, errorCallback) {
        var deferred = $.Deferred();

        if (typeof callback === 'function') {
           deferred.done(callback);
        }

        if (typeof errorCallback === 'function') {
           deferred.fail(errorCallback);
        }

        var rpc = {
            params : params,
            method : method,
            version: "1.1",
            id: String(Math.random()).slice(2),
        };
        
        var beforeSend = null;
        var token = (_auth_cb && typeof _auth_cb === 'function') ? _auth_cb()
            : (_auth.token ? _auth.token : null);
        if (token != null) {
            beforeSend = function (xhr) {
                xhr.setRequestHeader("Authorization", token);
            }
        }

        jQuery.ajax({
            url: _url,
            dataType: "text",
            type: 'POST',
            processData: false,
            data: JSON.stringify(rpc),
            beforeSend: beforeSend,
            success: function (data, status, xhr) {
                var result;
                try {
                    var resp = JSON.parse(data);
                    result = (numRets === 1 ? resp.result[0] : resp.result);
                } catch (err) {
                    deferred.reject({
                        status: 503,
                        error: err,
                        url: _url,
                        resp: data
                    });
                    return;
                }
                deferred.resolve(result);
            },
            error: function (xhr, textStatus, errorThrown) {
                var error;
                if (xhr.responseText) {
                    try {
                        var resp = JSON.parse(xhr.responseText);
                        error = resp.error;
                    } catch (err) { // Not JSON
                        error = "Unknown error - " + xhr.responseText;
                    }
                } else {
                    error = "Unknown Error";
                }
                deferred.reject({
                    status: 500,
                    error: error
                });
            }
        });
        return deferred.promise();
    }
}


