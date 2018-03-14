//
//  Purchases.qml
//  qml/hifi/commerce/purchases
//
//  Purchases
//
//  Created by Zach Fox on 2017-08-25
//  Copyright 2017 High Fidelity, Inc.
//
//  Distributed under the Apache License, Version 2.0.
//  See the accompanying file LICENSE or http://www.apache.org/licenses/LICENSE-2.0.html
//

import Hifi 1.0 as Hifi
import QtQuick 2.5
import QtQuick.Controls 1.4
import "../../../styles-uit"
import "../../../controls-uit" as HifiControlsUit
import "../../../controls" as HifiControls
import "../wallet" as HifiWallet
import "../common" as HifiCommerceCommon
import "../inspectionCertificate" as HifiInspectionCertificate

// references XXX from root context

Rectangle {
    HifiConstants { id: hifi; }

    id: root;
    property string activeView: "initialize";
    property string referrerURL: "";
    property bool securityImageResultReceived: false;
    property bool purchasesReceived: false;
    property bool punctuationMode: false;
    property bool pendingInventoryReply: true;
    property bool isShowingMyItems: false;
    property bool isDebuggingFirstUseTutorial: false;
    property int pendingItemCount: 0;
    property string installedApps;
    // Style
    color: hifi.colors.white;
    Connections {
        target: Commerce;

        onWalletStatusResult: {
            if (walletStatus === 0) {
                if (root.activeView !== "needsLogIn") {
                    root.activeView = "needsLogIn";
                }
            } else if ((walletStatus === 1) || (walletStatus === 2) || (walletStatus === 3)) {
                if (root.activeView !== "notSetUp") {
                    root.activeView = "notSetUp";
                    notSetUpTimer.start();
                }
            } else if (walletStatus === 4) {
                if (root.activeView !== "passphraseModal") {
                    root.activeView = "passphraseModal";
                    UserActivityLogger.commercePassphraseEntry("marketplace purchases");
                }
            } else if (walletStatus === 5) {
                if ((Settings.getValue("isFirstUseOfPurchases", true) || root.isDebuggingFirstUseTutorial) && root.activeView !== "firstUseTutorial") {
                    root.activeView = "firstUseTutorial";
                } else if (!Settings.getValue("isFirstUseOfPurchases", true) && root.activeView === "initialize") {
                    root.activeView = "purchasesMain";
                    root.installedApps = Commerce.getInstalledApps();
                    Commerce.inventory();
                    Commerce.getAvailableUpdates();
                }
            } else {
                console.log("ERROR in Purchases.qml: Unknown wallet status: " + walletStatus);
            }
        }

        onLoginStatusResult: {
            if (!isLoggedIn && root.activeView !== "needsLogIn") {
                root.activeView = "needsLogIn";
            } else {
                Commerce.getWalletStatus();
            }
        }

        onInventoryResult: {
            purchasesReceived = true;

            if (result.status !== 'success') {
                console.log("Failed to get purchases", result.message);
            } else if (!purchasesContentsList.dragging) { // Don't modify the view if the user's scrolling
                var inventoryResult = processInventoryResult(result.data.assets);

                var currentIndex = purchasesContentsList.currentIndex === -1 ? 0 : purchasesContentsList.currentIndex;
                purchasesModel.clear();
                purchasesModel.append(inventoryResult);

                root.pendingItemCount = 0;
                for (var i = 0; i < purchasesModel.count; i++) {
                    if (purchasesModel.get(i).status === "pending") {
                        root.pendingItemCount++;
                    }
                }

                if (previousPurchasesModel.count !== 0) {
                    checkIfAnyItemStatusChanged();
                } else {
                    // Fill statusChanged default value
                    // Not doing this results in the default being true...
                    for (var i = 0; i < purchasesModel.count; i++) {
                        purchasesModel.setProperty(i, "statusChanged", false);
                    }
                }
                previousPurchasesModel.append(inventoryResult);

                buildFilteredPurchasesModel();

                purchasesContentsList.positionViewAtIndex(currentIndex, ListView.Beginning);
            }

            if (root.pendingInventoryReply && root.pendingItemCount > 0) {
                inventoryTimer.start();
            }

            root.pendingInventoryReply = false;
        }

        onAvailableUpdatesResult: {
            if (result.status !== 'success') {
                console.log("Failed to get Available Updates", result.data.message);
            } else {
                sendToScript({method: 'purchases_availableUpdatesReceived', numUpdates: result.data.updates.length });
            }
        }
    }

    Timer {
        id: notSetUpTimer;
        interval: 200;
        onTriggered: {
            sendToScript({method: 'purchases_walletNotSetUp'});
        }
    }

    HifiInspectionCertificate.InspectionCertificate {
        id: inspectionCertificate;
        z: 999;
        visible: false;
        anchors.fill: parent;

        Connections {
            onSendToScript: {
                sendToScript(message);
            }
        }
    }

    HifiCommerceCommon.CommerceLightbox {
        id: lightboxPopup;
        visible: false;
        anchors.fill: parent;

        Connections {
            onSendToParent: {
                if (msg.method === 'commerceLightboxLinkClicked') {
                    Qt.openUrlExternally(msg.linkUrl);
                } else {
                    sendToScript(msg);
                }
            }
        }
    }

    //
    // TITLE BAR START
    //
    HifiCommerceCommon.EmulatedMarketplaceHeader {
        id: titleBarContainer;
        z: 998;
        visible: !needsLogIn.visible;
        // Size
        width: parent.width;
        // Anchors
        anchors.left: parent.left;
        anchors.top: parent.top;

        Connections {
            onSendToParent: {
                if (msg.method === 'needsLogIn' && root.activeView !== "needsLogIn") {
                    root.activeView = "needsLogIn";
                } else if (msg.method === 'showSecurityPicLightbox') {
                    lightboxPopup.titleText = "Your Security Pic";
                    lightboxPopup.bodyImageSource = msg.securityImageSource;
                    lightboxPopup.bodyText = lightboxPopup.securityPicBodyText;
                    lightboxPopup.button1text = "CLOSE";
                    lightboxPopup.button1method = "root.visible = false;"
                    lightboxPopup.button2text = "GO TO WALLET";
                    lightboxPopup.button2method = "sendToParent({method: 'purchases_openWallet'});";
                    lightboxPopup.visible = true;
                } else {
                    sendToScript(msg);
                }
            }
        }
    }
    MouseArea {
        enabled: titleBarContainer.usernameDropdownVisible;
        anchors.fill: parent;
        onClicked: {
            titleBarContainer.usernameDropdownVisible = false;
        }
    }
    //
    // TITLE BAR END
    //

    Rectangle {
        id: initialize;
        visible: root.activeView === "initialize";
        anchors.top: titleBarContainer.bottom;
        anchors.topMargin: -titleBarContainer.additionalDropdownHeight;
        anchors.bottom: parent.bottom;
        anchors.left: parent.left;
        anchors.right: parent.right;
        color: hifi.colors.white;

        Component.onCompleted: {
            securityImageResultReceived = false;
            purchasesReceived = false;
            Commerce.getWalletStatus();
        }
    }

    HifiWallet.NeedsLogIn {
        id: needsLogIn;
        visible: root.activeView === "needsLogIn";
        anchors.top: parent.top;
        anchors.bottom: parent.bottom;
        anchors.left: parent.left;
        anchors.right: parent.right;

        Connections {
            onSendSignalToWallet: {
                sendToScript(msg);
            }
        }
    }
    Connections {
        target: GlobalServices
        onMyUsernameChanged: {
            Commerce.getLoginStatus();
        }
    }

    HifiWallet.PassphraseModal {
        id: passphraseModal;
        visible: root.activeView === "passphraseModal";
        anchors.fill: parent;
        titleBarText: "Purchases";
        titleBarIcon: hifi.glyphs.wallet;

        Connections {
            onSendSignalToParent: {
                if (msg.method === "authSuccess") {
                    root.activeView = "initialize";
                    Commerce.getWalletStatus();
                } else {
                    sendToScript(msg);
                }
            }
        }
    }

    HifiCommerceCommon.FirstUseTutorial {
        id: firstUseTutorial;
        z: 999;
        visible: root.activeView === "firstUseTutorial";
        anchors.fill: parent;

        Connections {
            onSendSignalToParent: {
                switch (message.method) {
                    case 'tutorial_skipClicked':
                    case 'tutorial_finished':
                        Settings.setValue("isFirstUseOfPurchases", false);
                        root.activeView = "purchasesMain";
                        root.installedApps = Commerce.getInstalledApps();
                        Commerce.inventory();
                        Commerce.getAvailableUpdates();
                    break;
                }
            }
        }
    }

    //
    // PURCHASES CONTENTS START
    //
    Item {
        id: purchasesContentsContainer;
        visible: root.activeView === "purchasesMain";
        // Anchors
        anchors.left: parent.left;
        anchors.right: parent.right;
        anchors.top: titleBarContainer.bottom;
        anchors.topMargin: 8 - titleBarContainer.additionalDropdownHeight;
        anchors.bottom: parent.bottom;

        //
        // FILTER BAR START
        //
        Item {
            id: filterBarContainer;
            // Size
            height: 40;
            // Anchors
            anchors.left: parent.left;
            anchors.leftMargin: 8;
            anchors.right: parent.right;
            anchors.rightMargin: 16;
            anchors.top: parent.top;
            anchors.topMargin: 4;

            RalewayRegular {
                id: myText;
                anchors.top: parent.top;
                anchors.topMargin: 10;
                anchors.bottom: parent.bottom;
                anchors.bottomMargin: 10;
                anchors.left: parent.left;
                anchors.leftMargin: 16;
                width: paintedWidth;
                text: isShowingMyItems ? "My Items" : "My Purchases";
                color: hifi.colors.black;
                size: 22;
            }

            HifiControlsUit.TextField {
                id: filterBar;
                property string previousText: "";
                colorScheme: hifi.colorSchemes.faintGray;
                hasClearButton: true;
                hasRoundedBorder: true;
                anchors.left: myText.right;
                anchors.leftMargin: 16;
                height: 39;
                anchors.verticalCenter: parent.verticalCenter;
                anchors.right: parent.right;
                placeholderText: "filter items";

                onTextChanged: {
                    buildFilteredPurchasesModel();
                    purchasesContentsList.positionViewAtIndex(0, ListView.Beginning)
                    filterBar.previousText = filterBar.text;
                }

                onAccepted: {
                    focus = false;
                }
            }
        }
        //
        // FILTER BAR END
        //

        HifiControlsUit.Separator {
            id: separator;
            colorScheme: 2;
            anchors.left: parent.left;
            anchors.right: parent.right;
            anchors.top: filterBarContainer.bottom;
            anchors.topMargin: 16;
        }

        ListModel {
            id: purchasesModel;
        }
        ListModel {
            id: previousPurchasesModel;
        }
        HifiCommerceCommon.SortableListModel {
            id: tempPurchasesModel;
        }
        HifiCommerceCommon.SortableListModel {
            id: filteredPurchasesModel;
        }

        ListView {
            id: purchasesContentsList;
            visible: (root.isShowingMyItems && filteredPurchasesModel.count !== 0) || (!root.isShowingMyItems && filteredPurchasesModel.count !== 0);
            clip: true;
            model: filteredPurchasesModel;
            snapMode: ListView.SnapToItem;
            // Anchors
            anchors.top: separator.bottom;
            anchors.topMargin: 12;
            anchors.left: parent.left;
            anchors.bottom: parent.bottom;
            width: parent.width;
            delegate: PurchasedItem {
                itemName: title;
                itemId: id;
                itemPreviewImageUrl: preview;
                itemHref: download_url;
                certificateId: certificate_id;
                purchaseStatus: status;
                purchaseStatusChanged: statusChanged;
                itemEdition: model.edition_number;
                numberSold: model.number_sold;
                limitedRun: model.limited_run;
                displayedItemCount: model.displayedItemCount;
                permissionExplanationCardVisible: model.permissionExplanationCardVisible;
                isInstalled: model.isInstalled;
                upgradeUrl: model.upgrade_url;
                upgradeTitle: model.upgrade_title;
                isShowingMyItems: root.isShowingMyItems;
                itemType: {
                    if (model.root_file_url.indexOf(".fst") > -1) {
                        "avatar";
                    } else if (model.categories.indexOf("Wearables") > -1) {
                        "wearable";
                    } else if (model.root_file_url.endsWith('.json.gz')) {
                        "contentSet";
                    } else if (model.root_file_url.endsWith('.app.json')) {
                        "app";
                    } else if (model.root_file_url.endsWith('.json')) {
                        "entity";
                    } else {
                        "unknown";
                    }
                }
                anchors.topMargin: 10;
                anchors.bottomMargin: 10;

                Connections {
                    onSendToPurchases: {
                        if (msg.method === 'purchases_itemInfoClicked') {
                            sendToScript({method: 'purchases_itemInfoClicked', itemId: itemId});
                        } else if (msg.method === "purchases_rezClicked") {
                            sendToScript({method: 'purchases_rezClicked', itemHref: itemHref, itemType: itemType});
                        } else if (msg.method === 'purchases_itemCertificateClicked') {
                            inspectionCertificate.visible = true;
                            inspectionCertificate.isLightbox = true;
                            sendToScript(msg);
                        } else if (msg.method === "showInvalidatedLightbox") {
                            lightboxPopup.titleText = "Item Invalidated";
                            lightboxPopup.bodyText = 'Your item is marked "invalidated" because this item has been suspended ' +
                            "from the Marketplace due to a claim against its author.";
                            lightboxPopup.button1text = "CLOSE";
                            lightboxPopup.button1method = "root.visible = false;"
                            lightboxPopup.visible = true;
                        } else if (msg.method === "showPendingLightbox") {
                            lightboxPopup.titleText = "Item Pending";
                            lightboxPopup.bodyText = 'Your item is marked "pending" while your purchase is being confirmed. ' +
                            "Usually, purchases take about 90 seconds to confirm.";
                            lightboxPopup.button1text = "CLOSE";
                            lightboxPopup.button1method = "root.visible = false;"
                            lightboxPopup.visible = true;
                        } else if (msg.method === "showReplaceContentLightbox") {
                            lightboxPopup.titleText = "Replace Content";
                            lightboxPopup.bodyText = "Rezzing this content set will replace the existing environment and all of the items in this domain. " +
                                "If you want to save the state of the content in this domain, create a backup before proceeding.<br><br>" +
                                "For more information about backing up and restoring content, " +
                                "<a href='https://docs.highfidelity.com/create-and-explore/start-working-in-your-sandbox/restoring-sandbox-content'>" +
                                "click here to open info on your desktop browser.";
                            lightboxPopup.button1text = "CANCEL";
                            lightboxPopup.button1method = "root.visible = false;"
                            lightboxPopup.button2text = "CONFIRM";
                            lightboxPopup.button2method = "Commerce.replaceContentSet('" + msg.itemHref + "'); root.visible = false;";
                            lightboxPopup.visible = true;
                        } else if (msg.method === "showChangeAvatarLightbox") {
                            lightboxPopup.titleText = "Change Avatar";
                            lightboxPopup.bodyText = "This will change your current avatar to " + msg.itemName + " while retaining your wearables.";
                            lightboxPopup.button1text = "CANCEL";
                            lightboxPopup.button1method = "root.visible = false;"
                            lightboxPopup.button2text = "CONFIRM";
                            lightboxPopup.button2method = "MyAvatar.useFullAvatarURL('" + msg.itemHref + "'); root.visible = false;";
                            lightboxPopup.visible = true;
                        } else if (msg.method === "showPermissionsExplanation") {
                            if (msg.itemType === "entity") {
                                lightboxPopup.titleText = "Rez Certified Permission";
                                lightboxPopup.bodyText = "You don't have permission to rez certified items in this domain.<br><br>" +
                                    "Use the <b>GOTO app</b> to visit another domain or <b>go to your own sandbox.</b>";
                                lightboxPopup.button2text = "OPEN GOTO";
                                lightboxPopup.button2method = "sendToParent({method: 'purchases_openGoTo'});";
                            } else if (msg.itemType === "contentSet") {
                                lightboxPopup.titleText = "Replace Content Permission";
                                lightboxPopup.bodyText = "You do not have the permission 'Replace Content' in this <b>domain's server settings</b>. The domain owner " +
                                    "must enable it for you before you can replace content sets in this domain.";
                            }
                            lightboxPopup.button1text = "CLOSE";
                            lightboxPopup.button1method = "root.visible = false;"
                            lightboxPopup.visible = true;
                        } else if (msg.method === "setFilterText") {
                            filterBar.text = msg.filterText;
                        } else if (msg.method === "openPermissionExplanationCard") {
                            for (var i = 0; i < filteredPurchasesModel.count; i++) {
                                if (i !== index || msg.closeAll) {
                                    filteredPurchasesModel.setProperty(i, "permissionExplanationCardVisible", false);
                                } else {
                                    filteredPurchasesModel.setProperty(i, "permissionExplanationCardVisible", true);
                                }
                            }
                        } else if (msg.method === "updateItemClicked") {
                            sendToScript(msg);
                        }
                    }
                }
            }
        }

        Item {
            id: noItemsAlertContainer;
            visible: !purchasesContentsList.visible && root.purchasesReceived && root.isShowingMyItems && filterBar.text === "";
            anchors.top: filterBarContainer.bottom;
            anchors.topMargin: 12;
            anchors.left: parent.left;
            anchors.bottom: parent.bottom;
            width: parent.width;

            // Explanitory text
            RalewayRegular {
                id: noItemsYet;
                text: "<b>You haven't submitted anything to the Marketplace yet!</b><br><br>Submit an item to the Marketplace to add it to My Items.";
                // Text size
                size: 22;
                // Anchors
                anchors.top: parent.top;
                anchors.topMargin: 150;
                anchors.left: parent.left;
                anchors.leftMargin: 24;
                anchors.right: parent.right;
                anchors.rightMargin: 24;
                height: paintedHeight;
                // Style
                color: hifi.colors.baseGray;
                wrapMode: Text.WordWrap;
                // Alignment
                horizontalAlignment: Text.AlignHCenter;
            }

            // "Go To Marketplace" button
            HifiControlsUit.Button {
                color: hifi.buttons.blue;
                colorScheme: hifi.colorSchemes.dark;
                anchors.top: noItemsYet.bottom;
                anchors.topMargin: 20;
                anchors.horizontalCenter: parent.horizontalCenter;
                width: parent.width * 2 / 3;
                height: 50;
                text: "Visit Marketplace";
                onClicked: {
                    sendToScript({method: 'purchases_goToMarketplaceClicked'});
                }
            }
        }

        Item {
            id: noPurchasesAlertContainer;
            visible: !purchasesContentsList.visible && root.purchasesReceived && !root.isShowingMyItems && filterBar.text === "";
            anchors.top: filterBarContainer.bottom;
            anchors.topMargin: 12;
            anchors.left: parent.left;
            anchors.bottom: parent.bottom;
            width: parent.width;

            // Explanitory text
            RalewayRegular {
                id: haventPurchasedYet;
                text: "<b>You haven't purchased anything yet!</b><br><br>Get an item from <b>Marketplace</b> to add it to My Purchases.";
                // Text size
                size: 22;
                // Anchors
                anchors.top: parent.top;
                anchors.topMargin: 150;
                anchors.left: parent.left;
                anchors.leftMargin: 24;
                anchors.right: parent.right;
                anchors.rightMargin: 24;
                height: paintedHeight;
                // Style
                color: hifi.colors.baseGray;
                wrapMode: Text.WordWrap;
                // Alignment
                horizontalAlignment: Text.AlignHCenter;
            }

            // "Go To Marketplace" button
            HifiControlsUit.Button {
                color: hifi.buttons.blue;
                colorScheme: hifi.colorSchemes.dark;
                anchors.top: haventPurchasedYet.bottom;
                anchors.topMargin: 20;
                anchors.horizontalCenter: parent.horizontalCenter;
                width: parent.width * 2 / 3;
                height: 50;
                text: "Visit Marketplace";
                onClicked: {
                    sendToScript({method: 'purchases_goToMarketplaceClicked'});
                }
            }
        }
    }
    //
    // PURCHASES CONTENTS END
    //

    HifiControlsUit.Keyboard {
        id: keyboard;
        raised: HMD.mounted && filterBar.focus;
        numeric: parent.punctuationMode;
        anchors {
            bottom: parent.bottom;
            left: parent.left;
            right: parent.right;
        }
    }

    onVisibleChanged: {
        if (!visible) {
            inventoryTimer.stop();
        }
    }

    Timer {
        id: inventoryTimer;
        interval: 4000; // Change this back to 90000 after demo
        //interval: 90000;
        onTriggered: {
            if (root.activeView === "purchasesMain" && !root.pendingInventoryReply) {
                console.log("Refreshing Purchases...");
                root.pendingInventoryReply = true;
                Commerce.inventory();
                Commerce.getAvailableUpdates();
            }
        }
    }

    //
    // FUNCTION DEFINITIONS START
    //

    function processInventoryResult(inventory) {
        for (var i = 0; i < inventory.length; i++) {
            if (inventory[i].status.length > 1) {
                console.log("WARNING: Inventory result index " + i + " has a status of length >1!")
            }
            inventory[i].status = inventory[i].status[0];
            inventory[i].categories = inventory[i].categories.join(';');
        }
        return inventory;
    }

    function populateDisplayedItemCounts() {
        var itemCountDictionary = {};
        var currentItemId;
        for (var i = 0; i < filteredPurchasesModel.count; i++) {
            currentItemId = filteredPurchasesModel.get(i).id;
            if (itemCountDictionary[currentItemId] === undefined) {
                itemCountDictionary[currentItemId] = 1;
            } else {
                itemCountDictionary[currentItemId]++;
            }
        }

        for (var i = 0; i < filteredPurchasesModel.count; i++) {
            filteredPurchasesModel.setProperty(i, "displayedItemCount", itemCountDictionary[filteredPurchasesModel.get(i).id]);
        }
    }

    function sortByDate() {
        filteredPurchasesModel.sortColumnName = "purchase_date";
        filteredPurchasesModel.isSortingDescending = true;
        filteredPurchasesModel.valuesAreNumerical = true;
        filteredPurchasesModel.quickSort();
    }

    function buildFilteredPurchasesModel() {
        var sameItemCount = 0;
        
        tempPurchasesModel.clear();
        for (var i = 0; i < purchasesModel.count; i++) {
            if (purchasesModel.get(i).title.toLowerCase().indexOf(filterBar.text.toLowerCase()) !== -1) {
                if (!purchasesModel.get(i).valid) {
                    continue;
                }

                if (purchasesModel.get(i).status !== "confirmed" && !root.isShowingMyItems) {
                    tempPurchasesModel.insert(0, purchasesModel.get(i));
                } else if ((root.isShowingMyItems && purchasesModel.get(i).edition_number === "0") ||
                (!root.isShowingMyItems && purchasesModel.get(i).edition_number !== "0")) {
                    tempPurchasesModel.append(purchasesModel.get(i));
                }
            }
        }
        
        for (var i = 0; i < tempPurchasesModel.count; i++) {
            if (!filteredPurchasesModel.get(i)) {
                sameItemCount = -1;
                break;
            } else if (tempPurchasesModel.get(i).itemId === filteredPurchasesModel.get(i).itemId &&
            tempPurchasesModel.get(i).edition_number === filteredPurchasesModel.get(i).edition_number &&
            tempPurchasesModel.get(i).status === filteredPurchasesModel.get(i).status) {
                sameItemCount++;
            }
        }

        if (sameItemCount !== tempPurchasesModel.count || filterBar.text !== filterBar.previousText) {
            filteredPurchasesModel.clear();
            var currentId;
            for (var i = 0; i < tempPurchasesModel.count; i++) {
                currentId = tempPurchasesModel.get(i).id;
                
                if (!purchasesModel.get(i).valid) {
                    continue;
                }
                filteredPurchasesModel.append(tempPurchasesModel.get(i));
                filteredPurchasesModel.setProperty(i, 'permissionExplanationCardVisible', false);
                filteredPurchasesModel.setProperty(i, 'isInstalled', ((root.installedApps).indexOf(currentId) > -1));
            }

            populateDisplayedItemCounts();
            sortByDate();
        }
    }

    function checkIfAnyItemStatusChanged() {
        var currentPurchasesModelId, currentPurchasesModelEdition, currentPurchasesModelStatus;
        var previousPurchasesModelStatus;
        for (var i = 0; i < purchasesModel.count; i++) {
            currentPurchasesModelId = purchasesModel.get(i).id;
            currentPurchasesModelEdition = purchasesModel.get(i).edition_number;
            currentPurchasesModelStatus = purchasesModel.get(i).status;

            for (var j = 0; j < previousPurchasesModel.count; j++) {
                previousPurchasesModelStatus = previousPurchasesModel.get(j).status;
                if (currentPurchasesModelId === previousPurchasesModel.get(j).id &&
                    currentPurchasesModelEdition === previousPurchasesModel.get(j).edition_number &&
                    currentPurchasesModelStatus !== previousPurchasesModelStatus) {
                    
                    purchasesModel.setProperty(i, "statusChanged", true);
                } else {
                    purchasesModel.setProperty(i, "statusChanged", false);
                }
            }
        }
    }

    //
    // Function Name: fromScript()
    //
    // Relevant Variables:
    // None
    //
    // Arguments:
    // message: The message sent from the JavaScript, in this case the Marketplaces JavaScript.
    //     Messages are in format "{method, params}", like json-rpc.
    //
    // Description:
    // Called when a message is received from a script.
    //
    function fromScript(message) {
        switch (message.method) {
            case 'updatePurchases':
                referrerURL = message.referrerURL;
                titleBarContainer.referrerURL = message.referrerURL;
                filterBar.text = message.filterText ? message.filterText : "";
            break;
            case 'inspectionCertificate_setCertificateId':
                inspectionCertificate.fromScript(message);
            break;
            case 'purchases_showMyItems':
                root.isShowingMyItems = true;
            break;
            default:
                console.log('Unrecognized message from marketplaces.js:', JSON.stringify(message));
        }
    }
    signal sendToScript(var message);

    //
    // FUNCTION DEFINITIONS END
    //
}
