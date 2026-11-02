var APP = APP || {};

APP.global = (function($) {

    function init() {
        registerEventHandler();
        initPage();
    }

    function registerEventHandler() {
        $(document).on('click', function(e) {
            if (!$(e.target).closest('nav').length) {
                $('nav').removeClass('mobile');
            }
        });

        $(document).on('click', '.nav-toggler', function(e) {
            $('nav').toggleClass('mobile');
            e.preventDefault();
            e.stopPropagation();
        });

        // Close drawer after choosing a page link
        $(document).on('click', 'nav ul li[data-page] a', function() {
            $('nav').removeClass('mobile');
        });
    }

    function initPage() {
        let currentPage = retrievePageFromUrl();
        loadPage(currentPage);
        //        $('#nav-title').text(hostname);
        document.title = hostname + " - " + currentPage;
    }

    function retrievePageFromUrl() {
        let parsedUrl = new URL(window.location.href);

        return parsedUrl.searchParams.has("page") ? parsedUrl.searchParams.get("page") : 'status';
    }

    function loadPage(currentPage) {
        console.log("Current page: %s", currentPage);

        $.ajax({
            type: "GET",
            url: "pages/" + currentPage + ".html?nocache=" + Math.floor(Date.now() / 1000),
            success: function(data) {
                $('#container').html(data);
                initPageModule(currentPage);
            },
            error: function(response) {
                console.log('error', response);
            }
        });
    }

    function initPageModule(module) {
        if (APP.hasOwnProperty(module)) {
            APP[module].init();
        } else {
            console.log('module %s not registered', module);
        }
    }

    return {
        init: init
    };

})(jQuery);