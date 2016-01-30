Messages = new Mongo.Collection 'messages'
Nodes = new Mongo.Collection 'nodes'
mq = null

if Meteor.isClient
    console.log 'Starting client'

    angular
        .module 'kalmon-web', [
            'ngAnimate',
            'ngAria',
            'ngMaterial',
            'angular-meteor',
            'angular.filter',
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
            '$mdDialog',
            '$mdMedia',
            ($scope, $reactive, $mdDialog, $mdMedia) ->
                @ctrlName = 'NodesCtrl'
                $reactive(@).attach $scope
                @selected = null

                @dtableOptions =
                    default:
                        columnMode: 'flex'
                        headerHeight: 44

                @dtableOptions.files = angular.copy @dtableOptions.default
                @dtableOptions.configuration = angular.copy @dtableOptions.default

                @removeFile = (filename) =>
                    confirm = $mdDialog
                        .confirm()
                        .title 'Would you like to delete this file?'
                        .textContent "Once deleted, the file \"#{filename}\" can not be recovered."
                        .ariaLabel 'Delete file'
                        .ok 'Yes, delete it.'
                        .cancel 'No, cancel.'
                    $mdDialog
                        .show confirm
                        .then () =>
                            @sendCommand 'files/remove',
                                file: filename
                            @sendCommand 'info'
                        , () ->
                            # Dialog closed

                @uploadFile = () =>
                    $mdDialog
                        .show
                            templateUrl: 'client/views/new_file_dialog.tpl.html'
                            parent: angular.element document.body
                            clickOutsideToClose: true
                            fullscreen: (($mdMedia 'sm') || ($mdMedia 'xs'))
                            controller: [
                                '$scope',
                                '$mdDialog'
                                ($scope, $mdDialog) ->
                                    $scope.file =
                                        file: null
                                        url: null
                                        content: null

                                    $scope.cancel = () ->
                                        $mdDialog.cancel()

                                    $scope.submit = () =>
                                        $mdDialog.hide $scope.file
                            ]
                        .then (result) =>
                            if result
                                if result.content
                                    @sendCommand 'files/create',
                                        file: result.file,
                                        content: result.content
                                    @sendCommand 'info'
                                else if result.url
                                    HTTP.get result.url, {}, (error, response) =>
                                        if not error
                                            @sendCommand 'files/create',
                                                file: result.file,
                                                content: response.content
                                            @sendCommand 'info'
                                        else
                                            console.log error
                        , () ->
                            # Dialog closed

                @editConfigurationEntry = (entry) =>
                    $mdDialog
                        .show
                            templateUrl: 'client/views/edit_value_dialog.tpl.html'
                            parent: angular.element document.body
                            clickOutsideToClose: true
                            fullscreen: (($mdMedia 'sm') || ($mdMedia 'xs'))
                            resolve:
                                entry: () ->
                                    return angular.copy entry
                            controller: [
                                '$scope',
                                '$mdDialog'
                                'entry'
                                ($scope, $mdDialog, entry) ->
                                    $scope.entry = entry

                                    $scope.cancel = () ->
                                        $mdDialog.cancel()

                                    $scope.submit = () ->
                                        $mdDialog.hide entry
                            ]
                        .then (result) =>
                            if result and (result.value != null)
                                @sendCommand 'cfg/set',
                                    key: result.key
                                    value: result.value
                                @sendCommand 'info'
                        , () ->
                            # Dialog closed

                @sendCommand = (type, data = {}, node = null) =>
                    if not node
                        node = @selected._id

                    if not node
                        return

                    Meteor.call 'sendNodeCommand', node, type, data

                @helpers
                    nodes: () ->
                        Nodes
                            .find {},
                                sort:
                                    _id: 1
        ]

if Meteor.isServer
    toType = (obj) ->
        return ({}).toString.call(obj).match(/\s([a-zA-Z]+)/)[1].toLowerCase()

    sendNodeCommand = (node, type, data = {}) ->
        data = JSON.stringify data
        mq.publish "/nodes/#{node}/commands/#{type}", data

        return 'OK'

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
                    ,
                        $set:
                            updatedAt: node.updatedAt

    updateNodeInfo = (nodeId) ->
        Nodes
            .upsert
                _id: nodeId
            ,
                $set:
                    updatedAt: new Date()

        node = Nodes
            .findOne
                _id: nodeId

        if not node
            return

        infoMessageQuery =
            node: node._id
            type: 'response'
            response: 'info'

        if node.infoMessageId and node.infoUpdatedAt
            infoMessageQuery._id =
                $ne: node.infoMessageId
            infoMessageQuery.createdAt =
                $gt: node.infoUpdatedAt

        infoMessage = Messages
            .findOne infoMessageQuery,
                sort:
                    createdAt: -1

        if infoMessage
            node.infoMessageId = infoMessage._id
            node.infoUpdatedAt = infoMessage.createdAt

            node.files = []

            for file in infoMessage.data.files
                node.files.push
                    name: file[0]
                    size: file[1]

            node.configuration = []

            for k, v of infoMessage.data.cfg
                node.configuration.push
                    key: k
                    type: toType v
                    value: v

        Nodes
            .upsert
                _id: nodeId
            , node

    Meteor
        .startup () ->
            console.log 'Starting server'

            console.log 'Create capped Messages collection'
            Messages._createCappedCollection 5242880, 5000

            console.log 'Updating node list'
            updateNodeList()

            console.log 'Initializing MQTT subscriber'
            mq = mqtt.connect 'mqtt://espnode:espnode@192.168.178.46:8889'
            mq.subscribe '/nodes/#'
            mq.on 'message', Meteor.bindEnvironment (topic, message) ->
                matches = /^\/nodes\/([^\/]+)(\/.*)$/.exec topic
                node = if matches then matches[1] else null
                topicPart = if matches.length >= 3 then matches[2] else null
                body = message.toString()
                data = null

                try
                    data = JSON.parse body

                message =
                    createdAt: new Date(),
                    topic: topic,
                    message: body,
                    data: data,
                    node: node,
                    type: 'unknown'

                if topicPart
                    if matches = /^\/commands\/(.+)$/.exec topicPart
                        message.type = 'command'
                        message.command = matches[1]

                    else if matches = /^\/responses\/(.+)$/.exec topicPart
                        message.type = 'response'
                        message.response = matches[1]

                Messages
                    .insert message

                if node
                    updateNodeInfo(node)

            console.log 'Defining client methods'
            Meteor
                .methods
                    sendNodeCommand: sendNodeCommand
