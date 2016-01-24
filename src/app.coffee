Messages = new Mongo.Collection 'messages'
Nodes = new Mongo.Collection 'nodes'

if Meteor.isClient
    console.log 'Starting client'

    angular
        .module 'kalmon-web', [
            'ngAnimate',
            'ngAria',
            'ngMaterial',
            'angular-meteor',
            'ui.router',
            'angularMoment',
            'data-table',
        ]
        .config [
            '$urlRouterProvider',
            '$locationProvider',
            '$stateProvider',
            ($urlRouterProvider, $locationProvider, $stateProvider) ->
                $urlRouterProvider
                    .otherwise '/home'

                $locationProvider
                    .html5Mode false

                $stateProvider
                    .state 'home',
                        url: '/home'
                        templateUrl: 'client/views/home.tpl.html'
                        controller: 'HomeCtrl'
                        controllerAs: 'home'
                    .state 'logs',
                        url: '/logs'
                        templateUrl: 'client/views/logs.tpl.html'
                        controller: 'LogsCtrl'
                        controllerAs: 'logs'
                    .state 'nodes',
                        url: '/nodes'
                        templateUrl: 'client/views/nodes.tpl.html'
                        controller: 'NodesCtrl'
                        controllerAs: 'nodes'
        ]
        .controller 'HomeCtrl', [
            '$scope',
            '$mdSidenav',
            '$state',
            ($scope, $mdSidenav, $state) ->
                @ctrlName = 'HomeCtrl'
                $scope.applicationName = 'Kalmon'

                $scope.toggleSidenav = (target) ->
                    $mdSidenav(target).toggle()

                $scope.goto = (state, stateParams = {}) ->
                    $state.go state, stateParams

                $scope.navigationItems = [
                        state: 'home',
                        icon: 'home',
                        label: 'Home'
                    ,
                        state: 'nodes',
                        icon: 'devices_other',
                        label: 'Nodes'
                    ,
                        state: 'logs',
                        icon: 'list',
                        label: 'Logs'
                ]
        ]
        .controller 'LogsCtrl', [
            '$scope',
            '$reactive',
            ($scope, $reactive) ->
                @ctrlName = 'LogsCtrl'
                $reactive(@).attach $scope

                @options =
                    columnMode: 'flex'
                    headerHeight: 44
                    # footerHeight: false

                @helpers
                    messages: () ->
                        Messages
                            .find {},
                                sort:
                                    createdAt: -1
        ]
        .controller 'NodesCtrl', [
            '$scope',
            '$reactive',
            ($scope, $reactive) ->
                @ctrlName = 'NodesCtrl'
                $reactive(@).attach $scope
                @selected = null

                @helpers
                    nodes: () ->
                        Nodes
                            .find {},
                                sort:
                                    _id: 1
        ]

if Meteor.isServer
    updateNodeList = () ->
        Messages
            .aggregate [
                {
                    $group:
                        _id: '$node',
                        updatedAt:
                            $max: '$createdAt'
                },
                {
                    $sort:
                        _id: 1
                }
            ]
            .forEach (node) ->
                Nodes
                    .upsert
                        _id: node._id
                    , node

    Meteor
        .startup () ->
            console.log 'Starting server'

            console.log 'Create capped Messages collection'
            Messages._createCappedCollection 5242880, 5000

            console.log 'Updating node list'
            updateNodeList()

            console.log 'Initializing MQTT subscriber'
            mq = mqtt.connect 'mqtt://espnode:espnode@127.0.0.1:8889'
            mq.subscribe '/nodes/#'
            mq.on 'message', Meteor.bindEnvironment (topic, message) ->
                matches = /^\/nodes\/([^\/]+)\/.*$/.exec topic
                node = if matches then matches[1] else null
                message = message.toString()
                data = null

                try
                    data = JSON.parse message

                Messages
                    .insert
                        createdAt: new Date(),
                        topic: topic,
                        message: message,
                        data: data,
                        node: node

                updateNodeList()
