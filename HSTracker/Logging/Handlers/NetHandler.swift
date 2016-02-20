/*
 * This file is part of the HSTracker package.
 * (c) Benjamin Michotte <bmichotte@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 *
 * Created on 19/02/16.
 */

import Foundation

class NetHandler {
    static func handle(line: String) {
        let regex = "ConnectAPI\\.GotoGameServer -- address=(.+), game=(.+), client=(.+), spectateKey=(.+)"
        if line.isMatch(NSRegularExpression.rx(regex)) {
            //let match = line.firstMatchWithDetails(NSRegularExpression.rx(regex))
            Game.instance.gameStart()
        }
    }
}
